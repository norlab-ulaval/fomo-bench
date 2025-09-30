#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common functions
source "${SCRIPT_DIR}/src/lib/pipeline_common.sh"

# --- Main Pipeline ---

# Initialize pipeline and load environment
init_pipeline

# Prepare output directory
prepare_output_directory

# Start SLAM services and verify they're running
if ! start_slam_services; then
    exit 1
fi

# Run bagfile playback
play_bagfile

# Run trajectory evaluation
run_evaluation

# Open the evaluation report
REPORT_PATH="$OUTPUT_PATH_HOST/trajectory_analysis.pdf"
open_report "$REPORT_PATH" "evaluation report"

# The script will exit here, and the 'trap' will run the cleanup function.
