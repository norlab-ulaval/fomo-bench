#!/bin/bash
# Common functions and variables for SLAM evaluation pipelines

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
readonly C_GRAY='\033[0;90m'

# --- Helper Functions for Logging ---
info() { echo -e "${C_BLUE}INFO: $1${C_RESET}"; }
success() { echo -e "${C_GREEN}SUCCESS: $1${C_RESET}"; }
warn() { echo -e "${C_YELLOW}WARN: $1${C_RESET}"; }
error() { echo -e "${C_RED}ERROR: $1${C_RESET}" >&2; }
debug() { echo -e "${C_GRAY}DEBUG: $1${C_RESET}" >&2; }

# --- Common Functions ---

# Function to be called on script exit or interruption (Ctrl+C)
stop_containers() {
    info "Stopping all containers."
    # Use the determined DOCKER_COMPOSE_CMD to ensure consistency
    ${DOCKER_COMPOSE_CMD:-docker compose} stop
    success "Stopping complete."
}

# Function to be called on script exit or interruption (Ctrl+C)
cleanup() {
    info "Running cleanup... Removing all related containers."
    # Use the determined DOCKER_COMPOSE_CMD to ensure consistency
    ${DOCKER_COMPOSE_CMD:-docker compose} down -v --remove-orphans
    success "Cleanup complete."
}

# Initialize common settings and environment
init_pipeline() {
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

    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        error "Docker is not running"
        exit 1
    fi

    # Load environment variables from .env
    set -o allexport
    source .env
    set +o allexport

    # Determine which docker-compose files to use
    DOCKER_COMPOSE_CMD="docker compose"
    if [[ "${DEV_DOCKER:-false}" == "true" ]]; then
        info "Development mode is enabled. Using local Dockerfile."
        DOCKER_COMPOSE_CMD="docker compose -f docker-compose.yaml -f docker-compose-dev.yaml"
    fi

    # Set a trap to run the cleanup function on EXIT signal
    trap cleanup EXIT
}

# Clean up previous run and prepare output directory
prepare_output_directory() {
    # Safety check before removing the output directory
    if [ -z "$OUTPUT_PATH_HOST" ]; then
        error "OUTPUT_PATH_HOST is not set in .env. Aborting to prevent accidental deletion."
        exit 1
    fi

    info "Checking if the output directory: $OUTPUT_PATH_HOST already exists"
    if [ -d "$OUTPUT_PATH_HOST" ]; then
        if [ "${OVERWRITE:-0}" -eq 1 ]; then
            info "Overwriting existing output directory"
            rm -rf "$OUTPUT_PATH_HOST"
        else
            error "The output directory already exists. Please remove it manually before proceeding."
            exit 1
        fi
    fi
    # Create the output directory for the new run
    mkdir -p "$OUTPUT_PATH_HOST"
}

save_slam_logs() {
    sleep 2
    docker logs run_slam > "${PROCESSING_PATH_HOST}/run_slam_${LOCALIZATION_DATE}.log"
}

# Start SLAM services and verify they're running
start_slam_services() {
    info "Performing initial cleanup..."
    # Stop any containers from a previous run
    $DOCKER_COMPOSE_CMD down -v --remove-orphans

    if [[ $MAPPING_DATE == $LOCALIZATION_DATE ]]; then
        info "Setting mapping to 1"
        export IS_MAPPING=1
    else
        info "Setting mapping to 0"
        export IS_MAPPING=0
    fi

    info "Starting SLAM services in the background..."
    # Start SLAM and odometry recorder in detached mode
    $DOCKER_COMPOSE_CMD up --no-attach run_slam --no-attach record_odometry --no-attach run_foxglove --attach play_bag --exit-code-from run_slam run_slam record_odometry run_foxglove play_bag
    # info "Verifying that background services are running..."
    # sleep 5 # Give services a moment to start or fail. Adjust if your SLAM system takes longer to initialize.

    # # Specifically check the 'run_slam' service, as it's the most likely to fail.
    # # We get a list of services with status "running" and check if run_slam is in it.
    # RUN_SLAM_STATUS=$($DOCKER_COMPOSE_CMD ps --services --filter "status=running" | grep -w "run_slam" || true)

    # if [ -z "$RUN_SLAM_STATUS" ]; then
    #     error "'run_slam' service failed to start or exited unexpectedly."
    #     info "Showing recent logs for 'run_slam' to help diagnose:"
    #     # Show the last 20 lines of the log to help the user.
    #     $DOCKER_COMPOSE_CMD logs --tail=20 run_slam
    #     # The script will exit here, and the 'trap' will run the cleanup function.
    #     return 1
    # else
    #     success "'run_slam' service started successfully."
    #     return 0
    # fi
}

# Run bagfile playback
play_bagfile() {
    info "Starting bagfile playback. This will block until finished..."
    success "Bagfile playback complete."
}

# Run trajectory evaluation
run_evaluation() {
    info "Running trajectory evaluation..."
    $DOCKER_COMPOSE_CMD up evaluate_trajectory
    success "Evaluation complete."
}

# Try to open a report file
open_report() {
    local report_path="$1"
    local report_name="${2:-report}"

    info "Attempting to open $report_name..."
    if [ -f "$report_path" ]; then
        # Try to open the report in a cross-platform way
        xdg-open "$report_path" 2>/dev/null || open "$report_path" 2>/dev/null || warn "Could not open $report_name automatically."
        success "$report_name is available at: $report_path"
    else
        error "$report_name not found at: $report_path"
    fi
}


# Function to run the pipeline for a given trajectory
eval_single_trajectory() {
    export BAGFILE_PATH_HOST=$1
    export CALIB_PATH_HOST=$1/calib
    export OUTPUT_FILE_NAME="${2}_${3}.txt" # name of the recorded odometry file

    export REFERENCE_TRAJECTORY_FILE_HOST=$1/gt.csv
    export ESTIMATED_TRAJECTORY_FILE_HOST=$OUTPUT_PATH_HOST/$OUTPUT_FILE_NAME

    export MAPPING_DATE=$2
    export LOCALIZATION_DATE=$3

    export PROCESSING_PATH_HOST=$PROCESSING_PATH_BASE/$MAPPING_DATE
    mkdir -p $PROCESSING_PATH_HOST

    if [ ! -d "$BAGFILE_PATH_HOST" ]; then
        error "Bagfile path: $BAGFILE_PATH_HOST does not exist on host"
        exit 1
    fi

    debug "Bagfile path: $BAGFILE_PATH_HOST on host"
    debug "Calibration path: $CALIB_PATH_HOST on host"
    debug "Odometry recording saves data to $OUTPUT_FILE_NAME"
    debug "Estimated trajectory is stored in $ESTIMATED_TRAJECTORY_FILE_HOST on host"
    debug "Saving tpm files to ${PROCESSING_PATH_HOST} on host"
    # Start SLAM services and verify they're running
    if ! start_slam_services; then
        return 1
    fi

    # Run bagfile playback
    play_bagfile

    # Stop all containers
    # stop_containers

    # Any container output should be saved at this point
    save_slam_logs

    #cleanup

    # Check if the method generated a trajectory file
    # This might be the case with SLAM methods that do loop closure
    # In that case, the recorded trajectory would be wrong.
    if [ -f "${PROCESSING_PATH_HOST}/trajectory.txt" ]; then
        info "Method generated a final trajectory file, replacing existing one..."
        mv $ESTIMATED_TRAJECTORY_FILE_HOST "${ESTIMATED_TRAJECTORY_FILE_HOST}_bak"
        cp "${PROCESSING_PATH_HOST}/trajectory.txt" "${ESTIMATED_TRAJECTORY_FILE_HOST}"
    fi

    # Run trajectory evaluation
    run_evaluation
}
