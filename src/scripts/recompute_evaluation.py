import os
import sys

from plot_confusion_matrix import main_conf_matrix
from trajectory_analysis import evaluate


def main():
    base_path_gt = (
        "/Users/mbo/Documents/norlab/FoMo/fomo-devel/data/evaluation/yellow/gt"
    )
    base_path = "/Users/mbo/Documents/norlab/FoMo/fomo-devel/data/evaluation/yellow/proprioceptive"
    input_path = os.path.join(base_path, "trajectories")
    output_path = os.path.join(base_path, "results")
    slam = "rtr"

    if not os.path.exists(base_path_gt):
        print(f"GT path {base_path_gt} does not exist.")
        sys.exit(1)
    if not os.path.exists(input_path):
        print(f"Input path {input_path} does not exist.")
        sys.exit(1)

    if not os.path.exists(output_path):
        os.makedirs(output_path)

    for path in sorted(os.listdir(input_path)):
        if path.endswith(".txt"):
            mapping_date = path.split("_")[0] + "_" + path.split("_")[1]
            localization_date = (
                path.split("_")[2] + "_" + path.split("_")[3].split(".")[0]
            )
            yaml_filename = os.path.join(
                output_path,
                f"{mapping_date}_{localization_date}.yaml",
            )
            try:
                est_file = os.path.join(input_path, path)
                localization_date_short = "-".join(
                    localization_date.split("_")[1].split("-")[:3]
                )
                gt_file = os.path.join(
                    base_path_gt, localization_date_short, localization_date, "gt.csv"
                )
                print(f"Processing {path}...")
                evaluate(
                    output_path,
                    gt_file,
                    est_file,
                    "kabsch",
                    mapping_date,
                    localization_date,
                    slam,
                    zero=True,
                )
            except Exception as e:
                with open(yaml_filename, "w") as _:
                    pass
                print(f"An error occurred: {e}", file=sys.stderr)
    main_conf_matrix(output_path, base_path.split("/")[-1])


if __name__ == "__main__":
    main()
