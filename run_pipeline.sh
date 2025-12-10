#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common functions
source "${SCRIPT_DIR}/src/lib/pipeline_common.sh"

# --- Main Pipeline ---
init_pipeline

eval_single_trajectory $BAGFILE_PATH_HOST $BAGFILE_NAME $BAGFILE_NAME

# The script will exit here, and the 'trap' will run the cleanup function.
