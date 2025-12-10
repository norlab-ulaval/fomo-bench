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
    if [[ "${DEV_DOCKER:-0}" == 1 ]]; then
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
            if [ "${RUN_SLAM:-0}" -eq 1 ]; then
                error "Output directory already exists. Please remove it manually before proceeding with SLAM."
                exit 1
            else
                info "Output directory already exists. Recomputing evaluation metrics..."
            fi
        fi
    fi
    # Create the output directory for the new run
    mkdir -p "$OUTPUT_PATH_HOST"
}

save_slam_logs() {
    sleep 2
    docker logs run_slam_1 > "${PROCESSING_PATH_HOST_1}/run_slam_${LOCALIZATION_DATE}.log"
    docker logs run_slam_2 > "${PROCESSING_PATH_HOST_2}/run_slam_${LOCALIZATION_DATE}.log"
    docker logs run_slam_3 > "${PROCESSING_PATH_HOST_3}/run_slam_${LOCALIZATION_DATE}.log"
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
    $DOCKER_COMPOSE_CMD up -d run_slam_1 run_slam_2 run_slam_3 record_odometry_1 record_odometry_2 record_odometry_3 run_foxglove

    info "Verifying that background services are running..."
    sleep 10 # Give services a moment to start or fail. Adjust if your SLAM system takes longer to initialize.

    check_slam_status "run_slam_1"
    check_slam_status "run_slam_2"
    check_slam_status "run_slam_3"
    
}

check_slam_status() {
    # Specifically check the 'service_name' service, as it's the most likely to fail.
    # We get a list of services with status "running" and check if 'service_name' is in it.
    service_name=$1
    RUN_SLAM_STATUS=$($DOCKER_COMPOSE_CMD ps --services --filter "status=running" | grep -w $service_name || true)

    if [ -z "$RUN_SLAM_STATUS" ]; then
        error "'${service_name}' service failed to start or exited unexpectedly."
        info "Showing recent logs for '${service_name}' to help diagnose:"
        # Show the last 20 lines of the log to help the user.
        $DOCKER_COMPOSE_CMD logs --tail=20 ${service_name}
        # The script will exit here, and the 'trap' will run the cleanup function.
        return 1
    else
        success "'${service_name}' service started successfully."
        return 0
    fi
}

# Run bagfile playback
play_bagfile() {
    info "Starting bagfile playback. This will block until finished..."
    $DOCKER_COMPOSE_CMD up play_bag
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

    export REFERENCE_TRAJECTORY_FILE_HOST=$1/gt.txt
    export OUTPUT_PATH_HOST_1=$OUTPUT_PATH_HOST/$OUTPUT_PREFIX_SLAM_1
    export OUTPUT_PATH_HOST_2=$OUTPUT_PATH_HOST/$OUTPUT_PREFIX_SLAM_2
    export OUTPUT_PATH_HOST_3=$OUTPUT_PATH_HOST/$OUTPUT_PREFIX_SLAM_3

    export ESTIMATED_TRAJECTORY_FILE_HOST_1=$OUTPUT_PATH_HOST_1/$OUTPUT_FILE_NAME
    export ESTIMATED_TRAJECTORY_FILE_HOST_2=$OUTPUT_PATH_HOST_2/$OUTPUT_FILE_NAME
    export ESTIMATED_TRAJECTORY_FILE_HOST_3=$OUTPUT_PATH_HOST_3/$OUTPUT_FILE_NAME

    export MAPPING_DATE=$2
    export LOCALIZATION_DATE=$3

    export PROCESSING_PATH_HOST_1=$PROCESSING_PATH_BASE/$OUTPUT_PREFIX_SLAM_1/$MAPPING_DATE
    export PROCESSING_PATH_HOST_2=$PROCESSING_PATH_BASE/$OUTPUT_PREFIX_SLAM_2/$MAPPING_DATE
    export PROCESSING_PATH_HOST_3=$PROCESSING_PATH_BASE/$OUTPUT_PREFIX_SLAM_3/$MAPPING_DATE
    mkdir -p $PROCESSING_PATH_HOST_1
    mkdir -p $PROCESSING_PATH_HOST_2
    mkdir -p $PROCESSING_PATH_HOST_3

    if [ ! -d "$BAGFILE_PATH_HOST" ]; then
        error "Bagfile path: $BAGFILE_PATH_HOST does not exist on host"
        exit 1
    fi

    if [ "${RUN_SLAM:-0}" -eq 1 ]; then
        debug "Bagfile path: $BAGFILE_PATH_HOST on host"
        debug "Calibration path: $CALIB_PATH_HOST on host"
        debug "Odometry recording saves data to $OUTPUT_FILE_NAME"
        debug "Estimated trajectory is stored in $ESTIMATED_TRAJECTORY_FILE_HOST_1 on host"
        debug "Estimated trajectory is stored in $ESTIMATED_TRAJECTORY_FILE_HOST_2 on host"
        debug "Estimated trajectory is stored in $ESTIMATED_TRAJECTORY_FILE_HOST_3 on host"
        debug "Saving tpm files to ${PROCESSING_PATH_HOST_1} on host"
        debug "Saving tpm files to ${PROCESSING_PATH_HOST_2} on host"
        debug "Saving tpm files to ${PROCESSING_PATH_HOST_3} on host"
        # Start SLAM services and verify they're running
        if ! start_slam_services; then
            return 1
        fi

        # Start resource monitoring services
        info "Starting SLAM monitoring services..."
        # Stop any existing monitoring services

        info "Starting SLAM monitoring services in the background..."
        python src/scripts/container_stats_monitor.py --name  run_slam_1 -o $PROCESSING_PATH_HOST_1/stats_${LOCALIZATION_DATE}.json &
        stats_pid_1=$!
        python src/scripts/container_stats_monitor.py --name  run_slam_2 -o $PROCESSING_PATH_HOST_2/stats_${LOCALIZATION_DATE}.json &
        stats_pid_2=$!
        python src/scripts/container_stats_monitor.py --name  run_slam_3 -o $PROCESSING_PATH_HOST_3/stats_${LOCALIZATION_DATE}.json &
        stats_pid_3=$!

        python src/scripts/container_stats_monitor.py --name  play_bag -o $PROCESSING_PATH_BASE/stats_playbag_${MAPPING_DATE}_${LOCALIZATION_DATE}.json &
        stats_pid_rosbag=$!

        # Run bagfile playback
        play_bagfile

        # Stop all containers
        stop_containers

        # Stop all monitoring services
        kill $stats_pid_1
        kill $stats_pid_2
        kill $stats_pid_3
        kill $stats_pid_rosbag
        info "All monitoring services terminated"

        # Any container output should be saved at this point
        save_slam_logs

        cleanup

        # Check if the method generated a trajectory file
        # This might be the case with SLAM methods that do loop closure
        # In that case, the recorded trajectory would be wrong.
        if [ -f "${PROCESSING_PATH_HOST_1}/trajectory.txt" ]; then
            info "Method generated a final trajectory file, replacing existing one..."
            mv $ESTIMATED_TRAJECTORY_FILE_HOST_1 "${ESTIMATED_TRAJECTORY_FILE_HOST_1}_bak"
            cp "${PROCESSING_PATH_HOST_1}/trajectory.txt" "${ESTIMATED_TRAJECTORY_FILE_HOST_1}"
        fi
        if [ -f "${PROCESSING_PATH_HOST_2}/trajectory.txt" ]; then
            info "Method generated a final trajectory file, replacing existing one..."
            mv $ESTIMATED_TRAJECTORY_FILE_HOST_2 "${ESTIMATED_TRAJECTORY_FILE_HOST_2}_bak"
            cp "${PROCESSING_PATH_HOST_2}/trajectory.txt" "${ESTIMATED_TRAJECTORY_FILE_HOST_2}"
        fi
        if [ -f "${PROCESSING_PATH_HOST_3}/trajectory.txt" ]; then
            info "Method generated a final trajectory file, replacing existing one..."
            mv $ESTIMATED_TRAJECTORY_FILE_HOST_3 "${ESTIMATED_TRAJECTORY_FILE_HOST_3}_bak"
            cp "${PROCESSING_PATH_HOST_3}/trajectory.txt" "${ESTIMATED_TRAJECTORY_FILE_HOST_3}"
        fi
    fi

    # Run trajectory evaluation
    run_evaluation
}
