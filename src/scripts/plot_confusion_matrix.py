import numpy as np
import matplotlib.pyplot as plt
import argparse
import yaml
import os


def create_deployment_mapping():
    deployment_mapping = {
        "2024-11-21": "Nov21",
        "2024-11-28": "Nov28",
        "2025-01-10": "Jan10",
        "2025-01-29": "Jan29",
        "2025-01-30": "Jan29",
        "2025-03-10": "Mar",
        "2025-03-14": "Mar",
        "2025-04-16": "Apr",
        "2025-05-28": "May",
        "2025-06-26": "Jun",
        "2025-08-20": "Aug",
        "2025-09-24": "Sep",
    }
    return deployment_mapping


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Evaluate trajectories using APE and RPE metrics."
    )
    parser.add_argument("--slam", default="", help="Named of the SLAM used")
    parser.add_argument(
        "--path", default="/evaluation_output", help="Directory containing the results"
    )
    return parser.parse_args()


def get_traj_names_from_file_name(file_name):
    return file_name.split("_")[1], file_name.split("_")[3]


def construct_matrices(path: str):
    # get the number of yaml files in the directory
    yaml_files = [f for f in os.listdir(path) if f.endswith(".yaml")]
    yaml_files.sort()
    unique_map_names = []
    unique_loc_names = []
    for f in yaml_files:
        map_traj, loc_traj = get_traj_names_from_file_name(f)
        unique_map_names.append(map_traj)
        unique_loc_names.append(loc_traj)
    unique_map_names = sorted(list(set(unique_map_names)))
    unique_loc_names = sorted(list(set(unique_loc_names)))

    number_of_deployments_map = len(unique_map_names)
    number_of_deployments_loc = len(unique_loc_names)

    ape_matrix = np.zeros((number_of_deployments_map, number_of_deployments_loc))
    rpe_matrix = np.zeros((number_of_deployments_map, number_of_deployments_loc))

    unique_map_name_index_map = {name: i for i, name in enumerate(unique_map_names)}
    unique_loc_name_index_map = {name: i for i, name in enumerate(unique_loc_names)}

    labels_maps = []
    labels_locs = []
    deployment_mapping = create_deployment_mapping()

    for f in yaml_files:
        map_traj, loc_traj = get_traj_names_from_file_name(f)
        with open(os.path.join(path, f), "r") as file:
            data = yaml.safe_load(file)
            # Process data here
            #
            ape = data["results"]["ate_rmse_meters"]
            rpe = []
            for delta in range(100, 801, 100):
                relative_drift = (
                    100 * data["rpe_details"][f"{delta}m"]["rmse_meters"] / delta
                )
                rpe.append(relative_drift)
            rpe = np.mean(rpe)
            map_idx = unique_map_name_index_map[map_traj]
            loc_idx = unique_loc_name_index_map[loc_traj]
            # Update the matrices
            ape_matrix[map_idx, loc_idx] = ape
            rpe_matrix[map_idx, loc_idx] = rpe

            if len(labels_maps) < number_of_deployments_map:
                for key in deployment_mapping.keys():
                    if key in f:
                        label = deployment_mapping[key]
                        if label not in labels_maps:
                            labels_maps.append(label)

            if len(labels_locs) < number_of_deployments_loc:
                for key in deployment_mapping.keys():
                    if key in f:
                        label = deployment_mapping[key]
                        if label not in labels_locs:
                            labels_locs.append(label)

    return ape_matrix, rpe_matrix, labels_maps, labels_locs


def plot_confusion_matrix(matrix, labels_maps, labels_locs, title, ax, cmap="Reds"):
    """
    Plot confusion matrix with values and colors.
    """
    # Create a masked array to handle NaN values
    masked_matrix = np.ma.masked_where(np.isnan(matrix), matrix)

    # Create heatmap
    im = ax.imshow(
        masked_matrix,
        cmap=cmap,
        aspect="equal",
        vmin=np.nanmin(matrix),
        vmax=np.nanmax(matrix),
    )

    # Add colorbar
    cbar = plt.colorbar(im, ax=ax, shrink=0.8)
    cbar.set_label("Value", rotation=90, labelpad=15)

    # Set ticks and labels
    ax.set_xticks(range(len(labels_locs)))
    ax.set_yticks(range(len(labels_maps)))
    ax.set_xticklabels(labels_locs)
    ax.set_yticklabels(labels_maps)

    # Add text annotations
    for i in range(matrix.shape[0]):
        for j in range(matrix.shape[1]):
            if not np.isnan(matrix[i, j]):
                # Choose text color based on background intensity
                text_color = (
                    "white"
                    if masked_matrix[i, j] > (np.nanmax(matrix) * 0.6)
                    else "black"
                )
                ax.text(
                    j,
                    i,
                    f"{matrix[i, j]:.3f}",
                    ha="center",
                    va="center",
                    color=text_color,
                    fontweight="bold",
                    fontsize=10,
                )
            else:
                # Mark empty cells
                ax.text(j, i, "N/A", ha="center", va="center", color="gray", fontsize=8)

    # Labels and title
    ax.set_xlabel("Localization Deployment", fontsize=12, fontweight="bold")
    ax.set_ylabel("Mapping Deployment", fontsize=12, fontweight="bold")
    ax.set_title(title, fontsize=14, fontweight="bold", pad=20)

    # Add grid
    ax.set_xticks(np.arange(-0.5, len(labels_locs), 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(labels_maps), 1), minor=True)
    ax.grid(which="minor", color="white", linestyle="-", linewidth=2)


if __name__ == "__main__":
    args = parse_arguments()
    base_path = args.path
    ape_matrix, rpe_matrix, labels_maps, labels_locs = construct_matrices(base_path)

    # Create the plot
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))
    # Plot ATE confusion matrix
    plot_confusion_matrix(
        ape_matrix, labels_maps, labels_locs, "APE Confusion Matrix", ax1, cmap="Reds"
    )

    # Plot RTE confusion matrix
    plot_confusion_matrix(
        rpe_matrix,
        labels_maps,
        labels_locs,
        f"Mean translation drift",
        ax2,
        cmap="Blues",
    )

    plt.suptitle(f"Evaluation {args.slam}", fontsize=16, fontweight="bold")

    # Adjust layout
    plt.tight_layout()

    # Optional: Save the plot
    plt.savefig(base_path + "/confusion_matrices.pdf", dpi=300, bbox_inches="tight")
    plt.savefig(base_path + "/confusion_matrices.jpg", dpi=300, bbox_inches="tight")
    plt.savefig(base_path + "/confusion_matrices.svg", dpi=300, bbox_inches="tight")

    plt.show()

    print("Confusion matrices plotted successfully!")
