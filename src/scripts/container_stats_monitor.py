#!/usr/bin/env python3
import argparse
import json
import re
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# Global variable for signal handler
output_file = None


def parse_bytes(s):
    """
    Parses a size string like '1.29MB', '726MiB', '59.4kB', '0B' into bytes.
    """
    s = s.strip()
    if s == "0B":
        return 0.0

    # regex to separate value and unit
    match = re.match(r"^([\d\.]+)\s*([A-Za-z]+)$", s)
    if not match:
        return 0.0

    value = float(match.group(1))
    unit = match.group(2)

    units = {
        "B": 1,
        "kB": 1000,
        "MB": 1000**2,
        "GB": 1000**3,
        "TB": 1000**4,
        "KiB": 1024,
        "MiB": 1024**2,
        "GiB": 1024**3,
        "TiB": 1024**4,
        # handle case variations
        "kb": 1000,
        "mb": 1000**2,
        "gb": 1000**3,
        "kib": 1024,
        "mib": 1024**2,
        "gib": 1024**3,
    }

    return value * units.get(unit, 1)


def parse_timestamp(ts_str):
    if ts_str.endswith("Z"):
        ts_str = ts_str[:-1] + "+00:00"
    return datetime.fromisoformat(ts_str)


def create_plot(json_file, plot_file):
    try:
        with open(json_file, "r") as f:
            data = json.load(f)
    except Exception as e:
        print(f"Error reading input file: {e}")
        return

    if not data:
        print("No data found in file.")
        return

    timestamps = []
    cpu_percs = []
    mem_usages = []  # in MiB
    block_io_reads = []  # in MB
    block_io_writes = []  # in MB
    net_io_rx = []  # in MB
    net_io_tx = []  # in MB

    for entry in data:
        try:
            ts = parse_timestamp(entry["timestamp"])

            # CPU
            cpu_val = float(entry["CPUPerc"].replace("%", ""))

            # Mem: "726MiB / 28.35GiB"
            mem_part = entry["MemUsage"].split("/")[0].strip()
            mem_bytes = parse_bytes(mem_part)
            mem_mib = mem_bytes / (1024**2)

            # BlockIO: "1.29MB / 0B" (Read / Write)
            bio_parts = entry["BlockIO"].split("/")
            bio_read_bytes = parse_bytes(bio_parts[0].strip())
            bio_write_bytes = parse_bytes(bio_parts[1].strip())

            # NetIO: "107kB / 59.4kB" (Rx / Tx)
            net_parts = entry["NetIO"].split("/")
            net_rx_bytes = parse_bytes(net_parts[0].strip())
            net_tx_bytes = parse_bytes(net_parts[1].strip())

            timestamps.append(ts)
            cpu_percs.append(cpu_val)
            mem_usages.append(mem_mib)
            block_io_reads.append(bio_read_bytes / (1000**2))  # MB
            block_io_writes.append(bio_write_bytes / (1000**2))  # MB
            net_io_rx.append(net_rx_bytes / (1000**2))  # MB
            net_io_tx.append(net_tx_bytes / (1000**2))  # MB

        except (ValueError, KeyError, IndexError):
            # print(f"Skipping malformed entry: {e}")
            continue

    if not timestamps:
        print("No valid data points to plot.")
        return

    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.dates as mdates
        import matplotlib.pyplot as plt

        # Plotting
        fig, axs = plt.subplots(4, 1, figsize=(12, 16), sharex=True)

        # CPU
        axs[0].plot(timestamps, cpu_percs, label="CPU Usage", color="tab:blue")
        axs[0].set_ylabel("CPU %")
        axs[0].set_title("CPU Usage Over Time")
        axs[0].grid(True)
        axs[0].legend()

        # Memory
        axs[1].plot(timestamps, mem_usages, label="Mem Usage (MiB)", color="tab:orange")
        axs[1].set_ylabel("Memory (MiB)")
        axs[1].set_title("Memory Usage")
        axs[1].grid(True)
        axs[1].legend()

        # Block IO
        axs[2].plot(timestamps, block_io_reads, label="Block Read", color="tab:green")
        axs[2].plot(
            timestamps,
            block_io_writes,
            label="Block Write",
            color="tab:red",
            linestyle="--",
        )
        axs[2].set_ylabel("Block I/O (MB)")
        axs[2].set_title("Block I/O")
        axs[2].grid(True)
        axs[2].legend()

        # Net IO
        axs[3].plot(timestamps, net_io_rx, label="Net Rx", color="tab:purple")
        axs[3].plot(
            timestamps, net_io_tx, label="Net Tx", color="tab:brown", linestyle="--"
        )
        axs[3].set_ylabel("Net I/O (MB)")
        axs[3].set_title("Network I/O")
        axs[3].grid(True)
        axs[3].legend()

        # Formatting x-axis
        axs[3].xaxis.set_major_formatter(mdates.DateFormatter("%H:%M:%S"))
        fig.autofmt_xdate()

        plt.tight_layout()
        plt.savefig(plot_file)
        plt.close(fig)
        print(f"Plot saved to {plot_file}")
    except ImportError:
        print("matplotlib not found, skipping figure generation.")


def signal_handler(sig, frame):
    """Handle Ctrl+C and SIGTERM gracefully"""
    if output_file:
        print(f"\nStats saved to {output_file}")
        try:
            plot_file = str(output_file).replace(".json", ".jpg")
            if plot_file == str(output_file):
                plot_file += ".jpg"
            print(f"Generating plot to {plot_file}...")
            create_plot(output_file, plot_file)
        except Exception as e:
            print(f"Error generating plot: {e}")

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

    # Set global output_file for signal handler
    output_file = Path(args.output).absolute()

    # Register signal handler for graceful shutdown
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    log_stats(args.name, output_file)
