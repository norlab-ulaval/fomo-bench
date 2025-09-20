#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# a pipeline's return status is the value of the last command to exit with a non-zero status,
# or zero if no command exited with a non-zero status
set -o pipefail

# --- Color Definitions ---
# Provides clear, color-coded feedback to the user.
readonly C_RESET='\033[0m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

# --- Helper Functions for Logging ---
info() { echo -e "${C_BLUE}INFO: $1${C_RESET}"; }
success() { echo -e "${C_GREEN}SUCCESS: $1${C_RESET}"; }
warn() { echo -e "${C_YELLOW}WARN: $1${C_RESET}"; }
error() { echo -e "${C_RED}ERROR: $1${C_RESET}" >&2; }

# --- Main Logic ---

# Function to be called on script exit or interruption (Ctrl+C)
cleanup() {
    info "Running cleanup... Stopping all related containers."
    # Use the determined DOCKER_COMPOSE_CMD to ensure consistency
    ${DOCKER_COMPOSE_CMD:-docker compose} down -v --remove-orphans
    success "Cleanup complete."
}

# Set a trap to run the cleanup function on EXIT signal
trap cleanup EXIT

# 1. --- Pre-flight Checks and Setup ---
info "Starting SLAM evaluation pipeline..."

# Check for .env file before proceeding
if [ ! -f .env ]; then
    error "Configuration file .env not found."
    if [ -f .env.example ]; then
        echo "Please create it by copying the example:"
        echo "  cp .env.example .env"
        echo "Then, modify .env to match your environment."
    fi
    exit 1
fi

# Load environment variables from .env
set -o allexport
source .env
set +o allexport



# --- Function to generate trajectory folder name ----
generate_trajectory_folder() {
    local deployment_folder=$1
    current_folder=$(pwd)
    cd $BASE_PATH_HOST/${deployment_folder}

    # Find the trajectory folder that matches the pattern
    local folder=$(ls -d $TARGET_TRAJECTORY* 2>/dev/null | head -n 1)
    cd $current_folder

    if [[ -n "$folder" ]]; then
        echo "$folder" # return the folder name
    else
        echo "No trajectory folder found for deployment: $deployment_folder" >&2
        return 1
    fi
}

# --- Function to run the pipeline for a given trajectory ----
run_pipeline() {
    export BAGFILE_PATH_HOST=$1
    export CALIB_PATH_HOST=$1/calib
    export OUTPUT_FILE_NAME="${2}_${3}.txt" # name of the recorded odometry file

    export REFERENCE_TRAJECTORY_FILE_HOST=$1/gt.csv
    export ESTIMATED_TRAJECTORY_FILE_HOST=$OUTPUT_PATH_HOST/$OUTPUT_FILE_NAME

    export MAPPING_DATE=$2
    export LOCALIZATION_DATE=$3

    export PROCESSING_PATH_HOST="/tmp/data/${MAPPING_DATE}"

    info "Starting SLAM services in the background..."
    info "Bagfile path: $BAGFILE_PATH_HOST"
    info "Calibration path: $CALIB_PATH_HOST"

    info "Odometry recording saves data to $OUTPUT_FILE_NAME"
    info "Estimated trajectory is stored in $ESTIMATED_TRAJECTORY_FILE_HOST on host"

    if [[ $MAPPING_DATE == $LOCALIZATION_DATE ]]; then
        export IS_MAPPING=1
    else
        export IS_MAPPING=0
    fi

    # --- Pipeline Cleanup ---
    info "Performing cleanup..."
    # Stop any containers from a previous run
    $DOCKER_COMPOSE_CMD down -v --remove-orphans

    # Start SLAM and odometry recorder in detached mode
    $DOCKER_COMPOSE_CMD up -d run_slam record_odometry run_foxglove

    info "Verifying that background services are running..."
    sleep 5 # Give services a moment to start or fail. Adjust if your SLAM system takes longer to initialize.

    # Specifically check the 'run_slam' service, as it's the most likely to fail.
    # We get a list of services with status "running" and check if run_slam is in it.
    RUN_SLAM_STATUS=$($DOCKER_COMPOSE_CMD ps --services --filter "status=running" | grep -w "run_slam" || true)

    if [ -z "$RUN_SLAM_STATUS" ]; then
        error "'run_slam' service failed to start or exited unexpectedly."
        info "Showing recent logs for 'run_slam' to help diagnose:"
        # Show the last 20 lines of the log to help the user.
        $DOCKER_COMPOSE_CMD logs --tail=20 run_slam
        # The script will exit here, and the 'trap' will run the cleanup function.
        exit 1
    else
        success "'run_slam' service started successfully."
    fi

    info "Starting bagfile playback. This will block until finished..."
    $DOCKER_COMPOSE_CMD up play_bag
    success "Bagfile playback complete."

    sleep 2

    # At this point, play_bag has finished, so we can stop the SLAM system.
    # The `trap` will handle the final `down` command, but we can be explicit here if needed.
    # For simplicity, we let the trap handle the final cleanup.

    # 4. --- Run Evaluation Stage ---
    info "Running trajectory evaluation..."
    $DOCKER_COMPOSE_CMD up evaluate_trajectory
    success "Evaluation complete."
}

# Determine which docker-compose files to use
DOCKER_COMPOSE_CMD="docker compose"
if [[ "${DEV_DOCKER:-false}" == "true" ]]; then
    info "Development mode is enabled. Using local Dockerfile."
    DOCKER_COMPOSE_CMD="docker compose -f docker-compose.yaml -f docker-compose-dev.yaml"
fi

# Safety check before removing the output directory
if [ -z "$OUTPUT_PATH_HOST" ]; then
    error "OUTPUT_PATH_HOST is not set in .env. Aborting..."
    exit 1
fi
info "Checking for an old output directory in: $OUTPUT_PATH_HOST"
# Only remove if the directory actually exists
if [ -d "$OUTPUT_PATH_HOST" ]; then
    rm -rf "$OUTPUT_PATH_HOST"
    success "Previous output directory removed."
else
    warn "Previous output directory not found. Nothing to remove."
fi
# Create the output directory for the new run
mkdir -p "$OUTPUT_PATH_HOST"


ROW_FOLDERS=("2024-11-21")
COL_FOLDERS=("2024-11-21" "2025-01-29" "2025-03-10" "2025-06-26")

for map_folder in "${ROW_FOLDERS[@]}"; do
    traj_row=$(generate_trajectory_folder "$map_folder")
    traj_row_path="${BASE_PATH_HOST}/${map_folder}/${traj_row}"

    # Check if input directories exist
    if [ ! -d "$traj_row_path" ]; then
        warn "Warning: Bag directory ${traj_row_path} does not exist, skipping..."
        continue
    fi

    run_pipeline "$traj_row_path" "$traj_row" "$traj_row"
    sleep 2

    for loc_folder in "${COL_FOLDERS[@]}"; do
        # skip the diagonal as we already evaluated it
        if [ "$map_folder" == "$loc_folder" ]; then
            continue
        fi

        traj_row=$(generate_trajectory_folder "$map_folder")
        traj_col=$(generate_trajectory_folder "$loc_folder")

        traj_row_path="${BASE_PATH_HOST}/${map_folder}/${traj_row}"
        traj_col_path="${BASE_PATH_HOST}/${loc_folder}/${traj_col}"

        # Check if input directories exist
        if [ ! -d "$traj_row_path" ]; then
            warn "Warning: Row directory $traj_row_path does not exist, skipping..."
            continue
        fi

        if [ ! -d "$traj_col_path" ]; then
            warn "Warning: Col directory $traj_col_path does not exist, skipping..."
            continue
        fi

        run_pipeline "$traj_col_path" "$traj_row" "$traj_col"
        sleep 2
    done
done

# 6. --- CONFUSION MATRIX ---
# Construct the final confusion matrix
CONFUSION_MATRIX_PATH="${OUTPUT_PATH_HOST}/confusion_matrices.pdf"
info "Creating confusion matrix..."
$DOCKER_COMPOSE_CMD up plot_confusion_matrix
success "Confusion matrix created."

info "Attempting to open confusion matrix..."
if [ -f "$CONFUSION_MATRIX_PATH" ]; then
    # Try to open the report in a cross-platform way
    xdg-open "$CONFUSION_MATRIX_PATH" 2>/dev/null || open "$CONFUSION_MATRIX_PATH" 2>/dev/null || warn "Could not open report automatically."
    success "Confusion matrix is available at: $CONFUSION_MATRIX_PATH"
else
    error "Confusion matrix not found at: $CONFUSION_MATRIX_PATH"
fi
