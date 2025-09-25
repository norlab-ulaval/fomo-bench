import os
import copy
import sys
import yaml
import argparse
import numpy as np
import matplotlib.pyplot as plt

from evo.tools import file_interface
from evo.core import sync, metrics
import evo.core.geometry as geometry
from evo.core.trajectory import PoseTrajectory3D
from evo.core import lie_algebra as lie

# =============================================================================
# Configuration and Data Loading
# =============================================================================
def parse_arguments():
    parser = argparse.ArgumentParser(description="Evaluate trajectories using APE and RPE metrics.")
    parser.add_argument("--mapping_date", default="",
                        help="Date of the deployment used for the mapping")
    parser.add_argument("--localization_date", default="",
                        help="Date of the deployment used for localization")
    parser.add_argument("--slam", default="",
                        help="Named of the SLAM used")
    parser.add_argument("--gt", default="/reference_trajectory.txt",
                        help="Path to the ground truth trajectory file")
    parser.add_argument("--est", default="/estimated_trajectory.txt",
                        help="Path to the estimated trajectory file")
    parser.add_argument("--output", default="/evaluation_output",
                        help="Directory to store output files")
    parser.add_argument("--test", action='store_true',
                        help="Use test mode with smaller RPE deltas")
    parser.add_argument("--alignment", default='start', const='all', nargs='?', choices=['start', 'full'], help='The alignment method to use. Start uses the first 1000 points, full uses all points')
    return parser.parse_args()

def load_trajectories(gt_file, est_file):
    traj_ref = file_interface.read_tum_trajectory_file(gt_file)
    traj_est = file_interface.read_tum_trajectory_file(est_file)
    return traj_ref, traj_est

# =============================================================================
# Trajectory Processing: Synchronization, Alignment & Orientation
# =============================================================================
def synchronize_trajectories(traj_ref, traj_est, max_diff=0.05):
    return sync.associate_trajectories(traj_ref, traj_est, max_diff)

def align_trajectories(traj_ref_sync, traj_est_sync, alignment):
    traj_ref_aligned = copy.deepcopy(traj_ref_sync)
    traj_est_aligned = copy.deepcopy(traj_est_sync)

    if alignment == "start":
        n = 100
    elif alignment == "full":
        n = -1
    elif alignment == "single":
        n = 1
    else:
        raise ValueError("Invalid alignment type")

    traj_est_aligned.align(traj_ref_aligned, correct_scale=False, correct_only_scale=False, n=n)
    return traj_ref_aligned, traj_est_aligned

def set_identity_orientations(traj):
    num_poses = len(traj.positions_xyz)
    identity_quats = np.zeros((num_poses, 4))
    identity_quats[:, 0] = 1
    return PoseTrajectory3D(
        positions_xyz=traj.positions_xyz,
        orientations_quat_wxyz=identity_quats,
        timestamps=traj.timestamps
    )

def process_trajectories(gt_file, est_file, alignment):
    if not os.path.exists(gt_file):
        print(f"File {gt_file} does not exist (gt_file)")
        exit(1)
    if not os.path.isfile(est_file):
        print(f"File {est_file} does not exist (est_file)")
        exit(1)

    try:
        traj_ref, traj_est = load_trajectories(gt_file, est_file)
    except Exception as e:
        print(f"Error loading trajectories: {e}")
        print(f"file paths: {gt_file} {est_file}")
        exit(1)

    traj_ref_sync, traj_est_sync = synchronize_trajectories(traj_ref, traj_est)
    traj_ref_sync, traj_est_sync = synchronize_trajectories(traj_ref, traj_est)
    traj_ref_aligned, traj_est_aligned = align_trajectories(traj_ref_sync, traj_est_sync, alignment)

    traj_ref_final = set_identity_orientations(traj_ref_aligned)
    traj_est_final = set_identity_orientations(traj_est_aligned)

    return traj_ref_final, traj_est_final

# =============================================================================
# Metric Computation: APE and RPE
# =============================================================================
def compute_ape(traj_pair):
    """
    Compute Absolute Pose Error (APE) using the translation part.
    """
    pose_relation = metrics.PoseRelation.translation_part
    ape_metric = metrics.APE(pose_relation)
    ape_metric.process_data(traj_pair)
    return ape_metric.get_statistic(metrics.StatisticsType.rmse), ape_metric.get_all_statistics()

def compute_rpe_for_delta(traj_pair, delta_meters):
    """
    Compute Relative Pose Error (RPE) for a given delta (in meters).
    Returns the computed statistics or None if processing fails.
    """
    pose_relation = metrics.PoseRelation.translation_part
    delta_unit = metrics.Unit.meters
    rpe_metric = metrics.RPE(pose_relation, delta_meters, delta_unit, all_pairs=True)

    try:
        rpe_metric.process_data(traj_pair)
    except Exception as e:
        print(f"Error processing RPE for delta {delta_meters}: {e}")
        return None

    return rpe_metric.get_all_statistics()

def compute_rpe_set(traj_pair, delta_list):
    """
    Compute RPE for a list of delta values.
    Returns a dictionary mapping delta to its statistics.
    """
    results = {}
    for delta in delta_list:
        stats = compute_rpe_for_delta(traj_pair, delta)
        if stats is not None:
            results[delta] = stats
        else:
            print(f"Skipping delta {delta} due to processing error.")
    return results

def create_rpe_table(rpe_results):
    """
    Create a table (list of lists) summarizing the RPE results.
    Also computes the average relative RPE.
    """
    table_data = []
    relative_rpe_values = []
    for delta, stats in rpe_results.items():
        rel_rpe = (stats['rmse'] / delta) * 100  # percentage
        relative_rpe_values.append(rel_rpe)
        table_data.append([
            f"{delta}m",
            f"RMSE: {rel_rpe:.2f}%\nSTD: {(stats['std'] / delta) * 100:.2f}%\n"
            f"MIN: {(stats['min'] / delta) * 100:.2f}%\nMAX: {(stats['max'] / delta) * 100:.2f}%",
            f"RMSE: {stats['rmse']:.3f} m\nSTD: {stats['std']:.3f} m\n"
            f"MIN: {stats['min']:.3f} m\nMAX: {stats['max']:.3f} m"
        ])
    avg_relative_rpe = float(np.mean(relative_rpe_values))
    return table_data, avg_relative_rpe

def compute_ate_rmse(rpe_results):
    """
    Compute an aggregated ATE RMSE value from RPE results.
    """
    rmse_values = [stats['rmse'] for stats in rpe_results.values()]
    return float(np.sqrt(np.mean(np.square(rmse_values))))

def export_results_to_yaml(filename, avg_relative_rpe, ate_rmse, rpe_results):
    """
    Save the computed metrics (average RPE and ATE RMSE along with detailed RPE stats) to a YAML file.
    """
    rpe_details = {
        f"{delta}m": {
            'rmse_meters': float(stats['rmse']),
            'std_meters': float(stats['std']),
            'min_meters': float(stats['min']),
            'max_meters': float(stats['max'])
        }
        for delta, stats in rpe_results.items()
    }
    data = {
        'results': {
            'rpe_avg_rmse_percentage': avg_relative_rpe,
            'ate_rmse_meters': ate_rmse
        },
        'rpe_details': rpe_details
    }
    with open(filename, 'w') as file:
        yaml.dump(data, file)

# =============================================================================
# Visualization Functions
# =============================================================================
def plot_trajectory_timestamp(ax, traj_ref, traj_est, coord: str):
    """
    Plot the given coordinates (reference and estimated) on the given axis
    as a function of time.
    """
    index = 0
    if coord.lower() == "x":
        index = 0
    elif coord.lower() == "y":
        index = 1
    elif coord.lower() == "z":
        index = 2
    error = np.abs(traj_ref.positions_xyz[:, index] - traj_est.positions_xyz[:, index])
    time = traj_ref.timestamps - traj_ref.timestamps[0]
    ax.plot(time, error,
            label=f"Error ({coord.capitalize()})", linestyle='-', marker='o', markersize=2)
    ax.set_xlabel("Time (s)")
    ax.set_ylabel(f"{coord.capitalize()} Error (m)")
    ax.set_title(f"{coord.capitalize()} Trajectory Error Plot")
    ax.grid()
    ax.set_aspect('equal', adjustable='datalim')

def plot_trajectory_xy(ax, traj_ref, traj_est):
    """
    Plot the XY trajectories (reference and estimated) on the given axis.
    """
    ax.plot(traj_ref.positions_xyz[:, 0], traj_ref.positions_xyz[:, 1],
            label="Reference", linestyle='-', marker='o', markersize=2)
    ax.plot(traj_est.positions_xyz[:, 0], traj_est.positions_xyz[:, 1],
            label="Estimated", linestyle='-', marker='x', markersize=2)
    ax.scatter(traj_ref.positions_xyz[0, 0], traj_ref.positions_xyz[0, 1], label="Start", color='red', marker='o', s=50)
    ax.scatter(traj_ref.positions_xyz[-1, 0], traj_ref.positions_xyz[-1, 1], label="End", color='blue', marker='x', s=50)
    ax.set_xlabel("X Position (m)")
    ax.set_ylabel("Y Position (m)")
    ax.set_title("XY Trajectory Plot")
    ax.legend()
    ax.grid()
    ax.set_aspect('equal', adjustable='datalim')

def set_equal_aspect_3d(ax, positions):
    """
    Set equal aspect ratio for a 3D plot based on trajectory positions.
    """
    x_limits = [np.min(positions[:, 0]), np.max(positions[:, 0])]
    y_limits = [np.min(positions[:, 1]), np.max(positions[:, 1])]
    z_limits = [np.min(positions[:, 2]), np.max(positions[:, 2])]
    max_range = max(np.ptp(x_limits), np.ptp(y_limits), np.ptp(z_limits))
    mid_x, mid_y, mid_z = np.mean(x_limits), np.mean(y_limits), np.mean(z_limits)
    ax.set_xlim(mid_x - max_range/2, mid_x + max_range/2)
    ax.set_ylim(mid_y - max_range/2, mid_y + max_range/2)
    ax.set_zlim(mid_z - max_range/2, mid_z + max_range/2)

def plot_trajectory_3d(ax, traj_ref, traj_est):
    """
    Plot the 3D trajectories on the given axis.
    """
    ax.plot(traj_ref.positions_xyz[:, 0], traj_ref.positions_xyz[:, 1], traj_ref.positions_xyz[:, 2],
            label="Reference")
    ax.plot(traj_est.positions_xyz[:, 0], traj_est.positions_xyz[:, 1], traj_est.positions_xyz[:, 2],
            label="Estimated")
    ax.set_xlabel("X Position (m)")
    ax.set_ylabel("Y Position (m)")
    ax.set_zlabel("Z Position (m)")
    ax.set_title("3D Trajectory Plot")
    ax.legend()
    ax.grid()
    set_equal_aspect_3d(ax, traj_ref.positions_xyz)

def plot_summary_table(ax, avg_relative_rpe, ate_rmse, mapping_date: str, localization_date: str, slam: str):
    """
    Plot a summary table of the computed metrics.
    """
    ax.axis('tight')
    ax.axis('off')
    ax.set_title(f"SUMMARY METRICS\n({mapping_date} to {localization_date})\nMethod: {slam}", fontsize=12, fontweight='bold')
    table_data = [[f"{avg_relative_rpe:.2f} %", f"{ate_rmse:.3f} m"]]
    col_labels = ["AVG RMSE RPE (%)", "ATE RMSE (m)"]
    table = ax.table(cellText=table_data, colLabels=col_labels, loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1.0, 2.4)

def plot_rpe_details_table(ax, rpe_table):
    """
    Plot a table showing detailed RPE results.
    """
    ax.axis('off')
    table = ax.table(cellText=rpe_table,
                     colLabels=["Delta", "Relative RPE", "Absolute RPE [m]"],
                     loc='center', cellLoc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(9)
    table.scale(1.0, 4.0)

def create_figure(traj_ref, traj_est, rpe_table, avg_relative_rpe, ate_rmse, save_path, mapping_date: str, localization_date: str, slam: str):
    """
    Create and save a figure with:
    - XY trajectory plot
    - Summary metrics table
    - 3D trajectory plot
    - RPE details table
    """
    fig, axs = plt.subplots(3, 2, figsize=(12, 16))

    # Summary Table
    plot_summary_table(axs[0, 0], avg_relative_rpe, ate_rmse, mapping_date, localization_date, slam)

    # RPE Details Table
    plot_rpe_details_table(axs[0, 1], rpe_table)

    plot_trajectory_timestamp(axs[1, 0], traj_ref, traj_est, "x")
    plot_trajectory_timestamp(axs[1, 1], traj_ref, traj_est, "y")
    plot_trajectory_timestamp(axs[2, 0], traj_ref, traj_est, "z")

    # XY Trajectory Plot
    plot_trajectory_xy(axs[2, 1], traj_ref, traj_est)

    # 3D Trajectory Plot (added as subplot 3)
    # ax_3d = fig.add_subplot(4, 2, 7, projection='3d')
    # plot_trajectory_3d(ax_3d, traj_ref, traj_est)

    plt.tight_layout()
    plt.savefig(f"{save_path}.pdf", format="pdf", dpi=300)
    plt.savefig(f"{save_path}.jpg", format="jpg", dpi=300)
    # plt.show()
    plt.close()

# =============================================================================
# Main Execution
# =============================================================================
if __name__ == '__main__':
    args = parse_arguments()
    os.makedirs(args.output, exist_ok=True)

    traj_pair = process_trajectories(args.gt, args.est, args.alignment)

    ape_rmse, ape_stats = compute_ape(traj_pair)

    TEST_DELTAS = [1, 2, 5, 10, 20, 50, 100]
    EVALUAITON_DELTAS = [5, 100, 200, 300, 400, 500, 600, 700, 800]
    DELTAS = TEST_DELTAS if args.test else EVALUAITON_DELTAS

    rpe_results = compute_rpe_set(traj_pair, DELTAS)

    if len(rpe_results) == 0:
        print("\033[91mToo big deltas! Try turning on test mode with --test\033[0m", file=sys.stderr)
        sys.exit(1)

    rpe_table, avg_relative_rpe = create_rpe_table(rpe_results)
    ate_rmse = compute_ate_rmse(rpe_results)

    yaml_filename = os.path.join(args.output, f"{args.mapping_date}_{args.localization_date}_trajectory_analysis.yaml")
    export_results_to_yaml(yaml_filename, avg_relative_rpe, ate_rmse, rpe_results)

    analysis_filename = os.path.join(args.output, f"{args.mapping_date}_{args.localization_date}_trajectory_analysis")
    create_figure(traj_pair[0], traj_pair[1], rpe_table, avg_relative_rpe, ate_rmse, analysis_filename, args.mapping_date, args.localization_date, args.slam)
