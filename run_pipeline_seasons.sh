#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common functions
source "${SCRIPT_DIR}/src/lib/pipeline_common.sh"

# --- Seasons-specific Functions ---

# Function to generate trajectory folder name
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

# Function to run the pipeline for a given trajectory
run_single_trajectory() {
    export BAGFILE_PATH_HOST=$1
    export CALIB_PATH_HOST=$1/calib
    export OUTPUT_FILE_NAME="${2}_${3}.txt" # name of the recorded odometry file

    export REFERENCE_TRAJECTORY_FILE_HOST=$1/gt.csv
    export ESTIMATED_TRAJECTORY_FILE_HOST=$OUTPUT_PATH_HOST/$OUTPUT_FILE_NAME

    export MAPPING_DATE=$2
    export LOCALIZATION_DATE=$3

    export PROCESSING_PATH_HOST="/tmp/data/${MAPPING_DATE}"
    mkdir -p $PROCESSING_PATH_HOST

    info "Bagfile path: $BAGFILE_PATH_HOST"
    info "Calibration path: $CALIB_PATH_HOST"
    info "Odometry recording saves data to $OUTPUT_FILE_NAME"
    info "Estimated trajectory is stored in $ESTIMATED_TRAJECTORY_FILE_HOST on host"

    if [[ $MAPPING_DATE == $LOCALIZATION_DATE ]]; then
        export IS_MAPPING=1
    else
        export IS_MAPPING=0
    fi

    # Start SLAM services and verify they're running
    if ! start_slam_services; then
        return 1
    fi

    # Run bagfile playback
    play_bagfile

    sleep 2

    # Save run_slam logs into a file for debugging
    docker logs run_slam > "${PROCESSING_PATH_HOST}/run_slam_${LOCALIZATION_DATE}.log"

    cleanup

    # Check if the method generated a trajectory file
    # This might be the case with SLAM methods that do loop closure
    # In that case, the recorded trajectory would be wrong.
    if [ -f "${PROCESSING_PATH_HOST}/trajectory.txt" ]; then
        info "Method generated a final trajectory file, replacing existing one..."
        mv $ESTIMATED_TRAJECTORY_FILE_HOST "${ESTIMATED_TRAJECTORY_FILE_HOST}_bak"
        mv "${PROCESSING_PATH_HOST}/trajectory.txt" "${ESTIMATED_TRAJECTORY_FILE_HOST}"
    fi

    # Run trajectory evaluation
    run_evaluation
}

# --- Main Pipeline ---

# Initialize pipeline and load environment
init_pipeline

# Prepare output directory
prepare_output_directory

# Run cross-seasonal evaluation
ROW_FOLDERS=("${TARGET_DEPLOYMENTS[@]}")
COL_FOLDERS=("${TARGET_DEPLOYMENTS[@]}")

for map_folder in "${ROW_FOLDERS[@]}"; do
    traj_row=$(generate_trajectory_folder "$map_folder")
    traj_row_path="${BASE_PATH_HOST}/${map_folder}/${traj_row}"

    # Check if input directories exist
    if [ ! -d "$traj_row_path" ]; then
        warn "Warning: Bag directory ${traj_row_path} does not exist, skipping..."
        continue
    fi

    run_single_trajectory "$traj_row_path" "$traj_row" "$traj_row"
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

        run_single_trajectory "$traj_col_path" "$traj_row" "$traj_col"
        sleep 2
    done
done

# Create and open confusion matrix
info "Creating confusion matrix..."
$DOCKER_COMPOSE_CMD up plot_confusion_matrix
success "Confusion matrix created."

CONFUSION_MATRIX_PATH="${OUTPUT_PATH_HOST}/confusion_matrices.pdf"
open_report "$CONFUSION_MATRIX_PATH" "confusion matrix"
