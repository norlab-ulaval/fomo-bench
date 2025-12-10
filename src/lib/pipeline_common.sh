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

    for i in "${!SLAM_IMAGES[@]}"; do
        slam_image="${SLAM_IMAGES[$i]}"
        slam_label=$(generate_slam_label "$slam_image")
        
        # Export variables for this specific SLAM instance
        export SLAM_IMAGE="$slam_image"
        export SLAM_LABEL="$slam_label"
        
        if [ -n "$slam_image" ]; then
            slam_label=$(generate_slam_label "$slam_image")
            docker compose -p "fomo-slam-${slam_label}" -f docker-compose.slam.yaml stop
        fi
    done
    
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

# Function to generate a label from the docker image name
generate_slam_label() {
    local image_name=$1
    # Remove registry prefix if present (everything before the last /)
    local label="${image_name##*/}"
    # Remove tag if present (everything after :)
    label="${label%%:*}"
    # Replace any incompatible characters with -
    label=$(printf "%s" "$label" | tr -c '[:alnum:]' '-')
    echo "$label"
}

save_slam_logs() {
    sleep 2
    # Loop to save logs for all dynamic instances
    for i in "${!SLAM_IMAGES[@]}"; do
        slam_image="${SLAM_IMAGES[$i]}"
        if [ -n "$slam_image" ]; then
            slam_label=$(generate_slam_label "$slam_image")
            
            # Determine processing path for this index
            proc_path="$PROCESSING_PATH_BASE/$slam_label/$MAPPING_DATE"
            
            docker logs "run_slam_${slam_label}" > "${proc_path}/run_slam_${LOCALIZATION_DATE}.log" 2>/dev/null || true
        fi
    done
}

# Start SLAM services and verify they're running
start_slam_services() {
    if [[ $MAPPING_DATE == $LOCALIZATION_DATE ]]; then
        info "Setting mapping to 1"
        export IS_MAPPING=1
    else
        info "Setting mapping to 0"
        export IS_MAPPING=0
    fi

    # Dynamically start SLAM services
    for i in "${!SLAM_IMAGES[@]}"; do
        slam_image="${SLAM_IMAGES[$i]}"
        
        if [ -n "$slam_image" ]; then
            slam_label=$(generate_slam_label "$slam_image")
            info "Starting SLAM service $((i+1)): $slam_image (Label: $slam_label)"

            # Export variables for this specific SLAM instance
            export SLAM_IMAGE="$slam_image"
            export SLAM_LABEL="$slam_label"
            
            # Determine output paths
            export OUTPUT_PATH_HOST="${OUTPUT_PATH_HOST_BASE}/${SLAM_LABEL}"
            export PROCESSING_PATH_HOST="${PROCESSING_PATH_BASE}/${SLAM_LABEL}/${MAPPING_DATE}"
            
            # Create directories
            mkdir -p "$OUTPUT_PATH_HOST"
            mkdir -p "$PROCESSING_PATH_HOST"

            # Launch the SLAM pair as a separate project
            docker compose -p "fomo-slam-${slam_label}" -f docker-compose.slam.yaml up -d --force-recreate
        fi
    done

    # Verify status
    info "Verifying that background services are running..."
    sleep 5
    for i in "${!SLAM_IMAGES[@]}"; do
        slam_image="${SLAM_IMAGES[$i]}"
        if [ -n "$slam_image" ]; then
            slam_label=$(generate_slam_label "$slam_image")
            check_slam_status "run_slam_${slam_label}"
        fi
    done
}

check_slam_status() {
    service_name=$1
    # We check if the container is running using docker directly since we have multiple projects now
    RUN_SLAM_STATUS=$(docker ps --filter "name=${service_name}" --filter "status=running" --format "{{.Names}}")

    if [ -z "$RUN_SLAM_STATUS" ]; then
        error "'${service_name}' service failed to start or exited unexpectedly."
        info "Showing recent logs for '${service_name}' to help diagnose:"
        docker logs --tail=20 ${service_name}
        return 1
    else
        success "'${service_name}' service started successfully."
        return 0
    fi
}

# Run bagfile playback
play_bagfile() {
    info "Starting bagfile playback. This will block until finished..."
    $DOCKER_COMPOSE_CMD up -d play_bag
    success "Bagfile playback complete."
}

# Run trajectory evaluation
run_evaluation() {
    for i in "${!SLAM_IMAGES[@]}"; do
        slam_image="${SLAM_IMAGES[$i]}"
        if [ -n "$slam_image" ]; then
            slam_label=$(generate_slam_label "$slam_image")

            # Export variables for this specific SLAM instance
            # REFERENCE_TRAJECTORY_FILE_HOST is stable between SLAMs
            export SLAM_IMAGE="$slam_image"
            export SLAM_LABEL="$slam_label"
            export ESTIMATED_TRAJECTORY_FILEPATH_HOST="${OUTPUT_PATH_HOST_BASE}/${slam_label}/${ESTIMATED_TRAJECTORY_FILENAME_HOST}"
            export OUTPUT_PATH_HOST="${OUTPUT_PATH_HOST_BASE}/${slam_label}"
            if [ -f "$ESTIMATED_TRAJECTORY_FILEPATH_HOST" ]; then
                info "Running trajectory evaluation for $slam_image..."
                $DOCKER_COMPOSE_CMD -p "fomo-slam-${slam_label}" up -d evaluate_trajectory --remove-orphans
            fi
        fi
    done
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

wait_for_message_queue() {
    info "Waiting for play_bag to load data in the message queue..."
    # Show how much memory does the service take in a loop
    prev_mem=""
    while true; do
        current_mem=$(docker stats play_bag --no-stream --format '{{.MemUsage}}' | cut -d'/' -f1 | sed 's/[^0-9.]//g')
        
        if [ -n "$prev_mem" ]; then
            # Calculate relative change percentage
            change=$(awk -v curr="$current_mem" -v prev="$prev_mem" 'BEGIN {
                if (prev != 0) {
                    diff = (curr - prev) / prev * 100
                    print diff
                } else {
                    print 0
                }
            }')
            
            echo -ne "\rMemory usage of play_bag: $(docker stats play_bag --no-stream --format '{{.MemUsage}}') | Change: ${change}%    "
            
            # Check if absolute change is less than 1%
            abs_change=$(awk -v c="$change" 'BEGIN {print (c < 0 ? -c : c)}')
            if (( $(awk -v a="$abs_change" 'BEGIN {print (a < 1 ? 1 : 0)}') )); then
                break
            fi
        else
            echo -ne "\rMemory usage of play_bag: $(docker stats play_bag --no-stream --format '{{.MemUsage}}') | Change: N/A    "
        fi
        
        prev_mem=$current_mem
        sleep 1
    done
    echo  # Print newline at the end
    success "Play bag is ready."
}


# Function to run the pipeline for a given trajectory
eval_single_trajectory() {
    export BAGFILE_PATH_HOST=$1
    export CALIB_PATH_HOST=$1/calib
    export OUTPUT_FILE_NAME="${2}_${3}.txt" # name of the recorded odometry file

    export REFERENCE_TRAJECTORY_FILE_HOST=$1/gt.txt
    
    # Store base output path and processing path
    export OUTPUT_PATH_HOST_BASE=$OUTPUT_PATH_HOST
    export PROCESSING_PATH_BASE=$PROCESSING_PATH_BASE # Already set in .env usually

    mkdir -p "$PROCESSING_PATH_BASE"
    mkdir -p "$OUTPUT_PATH_HOST_BASE"

    export MAPPING_DATE=$2
    export LOCALIZATION_DATE=$3
    export ESTIMATED_TRAJECTORY_FILENAME_HOST=${MAPPING_DATE}_${LOCALIZATION_DATE}.txt

    if [ ! -d "$BAGFILE_PATH_HOST" ]; then
        error "Bagfile path: $BAGFILE_PATH_HOST does not exist on host"
        exit 1
    fi

    if [ "${RUN_SLAM:-0}" -eq 1 ]; then
        monitoring_pids=()
        info "Performing initial cleanup..."
        stop_containers
        # Start the core services first
        info "Starting core services..."

        python src/scripts/container_stats_monitor.py --name play_bag -o "$PROCESSING_PATH_BASE/stats_playbag_${MAPPING_DATE}_${LOCALIZATION_DATE}.json" &
        monitoring_pids+=($!)

        $DOCKER_COMPOSE_CMD up -d run_foxglove play_bag
        wait_for_message_queue

        # Start resource monitoring services
        info "Starting SLAM monitoring services..."
        
        # Start SLAM services and verify they're running
        if ! start_slam_services; then
            return 1
        fi
        for i in "${!SLAM_IMAGES[@]}"; do
            slam_image="${SLAM_IMAGES[$i]}"
            if [ -n "$slam_image" ]; then
                slam_label=$(generate_slam_label "$slam_image")
                stats_path="$PROCESSING_PATH_BASE/$slam_label/$MAPPING_DATE/stats_${LOCALIZATION_DATE}.json"
                
                python src/scripts/container_stats_monitor.py --name "run_slam_${slam_label}" -o "$stats_path" &
                monitoring_pids+=($!)
            fi
        done

        # sending a resume service call
        info "Unpausing rosbag play..."
        $DOCKER_COMPOSE_CMD exec play_bag /bin/bash -c "source /opt/ros/humble/setup.bash && ros2 service call /rosbag2_player/resume rosbag2_interfaces/srv/Resume"

        # wait until play_bag is done
        info "Waiting for play_bag to finish..."
        $DOCKER_COMPOSE_CMD wait play_bag

        # Stop all containers
        stop_containers

        # Stop all monitoring services
        for pid in "${monitoring_pids[@]}"; do
            kill "$pid" 2>/dev/null || true
        done
        info "All monitoring services terminated"

        # Any container output should be saved at this point
        save_slam_logs
        
        cleanup

        # Trajectory file handling
       for i in "${!SLAM_IMAGES[@]}"; do
            slam_image="${SLAM_IMAGES[$i]}"
            if [ -n "$slam_image" ]; then
                slam_label=$(generate_slam_label "$slam_image")
                proc_path="$PROCESSING_PATH_BASE/$slam_label/$MAPPING_DATE"
                est_path="$OUTPUT_PATH_HOST_BASE/$slam_label/$OUTPUT_FILE_NAME"
                
                if [ -f "${proc_path}/trajectory.txt" ]; then
                    info "Method $slam_label generated a final trajectory file, replacing existing one..."
                    mv "$est_path" "${est_path}_bak" 2>/dev/null || true
                    cp "${proc_path}/trajectory.txt" "$est_path"
                fi
            fi
        done
    fi

    # Run trajectory evaluation
    run_evaluation
}
