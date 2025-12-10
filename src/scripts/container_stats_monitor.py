#!/usr/bin/env python3

import argparse
import json
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Global variable for signal handler
output_file = None


def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    if output_file:
        print(f"\nStats saved to {output_file}")
    sys.exit(0)


def get_container_stats(container_name):
    """Get Docker container stats as JSON"""
    result = subprocess.run(
        [
            "docker",
            "container",
            "stats",
            container_name,
            "--no-stream",
            "--format",
            "json",
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def log_stats(container_name: str, output_path: Path):
    stats_list = []
    err_ctr = 0
    err_msg = ""

    while True:
        try:
            stats = get_container_stats(container_name)
        except subprocess.CalledProcessError as e:
            err_msg = f"Error getting stats: {e}"
            stats = None
        except json.JSONDecodeError as e:
            err_msg = f"Error parsing JSON: {e}"
            stats = None

        if stats:
            # Add timestamp
            stats["timestamp"] = (
                datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
            )
            stats_list.append(stats)

            # Write to file after each collection
            with open(output_path, "w") as f:
                json.dump(stats_list, f, indent=2)
        else:
            err_ctr += 1
            if err_ctr > 5:
                print(
                    f"Failed to get stats for {container_name} after 5 attempts. Stopping. Error: {err_msg}"
                )
                break

        time.sleep(0.5)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Log Docker container stats to a JSON file with timestamps",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument("--name", help="Name or ID of the Docker container to monitor")

    parser.add_argument(
        "-o",
        "--output",
        required=True,
        help="Output path where the stats JSON file will be saved",
    )

    args = parser.parse_args()

    # Register signal handler for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)

    log_stats(args.name, Path(args.output).absolute())
