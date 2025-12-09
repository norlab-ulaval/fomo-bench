import argparse
from pathlib import Path
import matplotlib.pyplot as plt
from fomo_sdk.evaluation.utils import construct_matrix
from fomo_sdk.evaluation.visualization import plot_evaluation_matrix
from fomo_sdk.common.naming import Slam, get_slam_title


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Evaluate trajectories using APE and RPE metrics."
    )
    parser.add_argument(
        "--slam",
        default="",
        choices=[member.lower() for member in Slam.__members__],
        help="Name of the SLAM used",
    )
    parser.add_argument(
        "--path", default="/evaluation_output", help="Directory containing the results"
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_arguments()
    results_path = Path(args.path)
    ape_matrix, rpe_matrix, add_marker_matrix, labels_maps, labels_locs = (
        construct_matrix(results_path)
    )

    fig, ax = plt.subplots(1, 1)
    # Plot RTE confusion matrix
    plot_evaluation_matrix(
        rpe_matrix,
        add_marker_matrix,
        labels_maps,
        labels_locs,
        get_slam_title(args.slam),
        ax,
        cmap="Blues",
    )

    # Adjust layout
    plt.tight_layout()

    # Optional: Save the plot
    plt.savefig(
        results_path / f"confusion_matrix_{args.slam}.jpg", dpi=300, bbox_inches="tight"
    )
    plt.show()
