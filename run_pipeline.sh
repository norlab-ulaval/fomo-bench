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

# Determine which docker-compose files to use
DOCKER_COMPOSE_CMD="docker compose"
if [[ "${DEV_DOCKER:-false}" == "true" ]]; then
    info "Development mode is enabled. Using local Dockerfile."
    DOCKER_COMPOSE_CMD="docker compose -f docker-compose.yaml -f docker-compose-dev.yaml"
fi

# 2. --- Initial Cleanup ---
info "Performing initial cleanup..."
# Stop any containers from a previous run
$DOCKER_COMPOSE_CMD down -v --remove-orphans

# Safety check before removing the output directory
if [ -z "$OUTPUT_PATH_HOST" ]; then
    error "OUTPUT_PATH_HOST is not set in .env. Aborting to prevent accidental deletion."
    exit 1
fi
info "Removing previous output directory: $OUTPUT_PATH_HOST"
# Only remove if the directory actually exists
if [ -d "$OUTPUT_PATH_HOST" ]; then
    rm -rf "$OUTPUT_PATH_HOST"
    success "Previous output directory removed."
else
    warn "Previous output directory not found. Nothing to remove."
fi
# Create the output directory for the new run
mkdir -p "$OUTPUT_PATH_HOST"


info "Starting SLAM services in the background..."
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

# At this point, play_bag has finished, so we can stop the SLAM system.
# The `trap` will handle the final `down` command, but we can be explicit here if needed.
# For simplicity, we let the trap handle the final cleanup.

# 4. --- Run Evaluation Stage ---
info "Running trajectory evaluation..."
$DOCKER_COMPOSE_CMD up evaluate_trajectory
success "Evaluation complete."

# 5. --- Final Report ---
# Construct the report path safely from OUTPUT_PATH_HOST
REPORT_PATH="$OUTPUT_PATH_HOST/trajectory_analysis.pdf"
info "Attempting to open evaluation report..."
if [ -f "$REPORT_PATH" ]; then
    # Try to open the report in a cross-platform way
    xdg-open "$REPORT_PATH" 2>/dev/null || open "$REPORT_PATH" 2>/dev/null || warn "Could not open report automatically."
    success "Report is available at: $REPORT_PATH"
else
    error "Evaluation report not found at: $REPORT_PATH"
fi

# The script will exit here, and the 'trap' will run the cleanup function.
