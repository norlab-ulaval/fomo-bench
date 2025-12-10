import argparse
from pathlib import Path

from fomo_sdk.evaluation.trajectories import evaluate


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Evaluate trajectories using APE and RPE metrics."
    )
    parser.add_argument(
        "--mapping_date", default="", help="Date of the deployment used for the mapping"
    )
    parser.add_argument(
        "--localization_date",
        default="",
        help="Date of the deployment used for localization",
    )
    parser.add_argument("--slam", default="", help="Named of the SLAM used")
    parser.add_argument(
        "--gt",
        default="/reference_trajectory.txt",
        help="Path to the ground truth trajectory file",
    )
    parser.add_argument(
        "--est",
        default="/estimated_trajectory.txt",
        help="Path to the estimated trajectory file",
    )
    parser.add_argument(
        "--output",
        default="/evaluation_output",
        help="Directory to store output files",
    )
    parser.add_argument(
        "--zero",
        action="store_true",
        help="Transform the trajectories to start at the origin",
    )
    parser.add_argument(
        "--alignment",
        default="full",
        nargs="?",
        choices=["start", "full", "kabsch"],
        help="The alignment method to use. Start uses the first 100 points, full uses all points",
    )
    return parser.parse_args()


# =============================================================================
# Main Execution
# =============================================================================
if __name__ == "__main__":
    args = parse_arguments()
    evaluate(
        Path(args.output),
        Path(args.gt),
        Path(args.est),
        args.alignment,
        args.mapping_date,
        args.localization_date,
        args.slam,
        args.zero,
        export_yaml=True,
        export_figure=True,
    )
