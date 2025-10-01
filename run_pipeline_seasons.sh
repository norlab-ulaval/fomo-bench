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

    eval_single_trajectory "$traj_row_path" "$traj_row" "$traj_row"
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

        eval_single_trajectory "$traj_col_path" "$traj_row" "$traj_col"
        sleep 2
    done
done

# Create and open confusion matrix
info "Creating confusion matrix..."
$DOCKER_COMPOSE_CMD up plot_confusion_matrix
success "Confusion matrix created."

CONFUSION_MATRIX_PATH="${OUTPUT_PATH_HOST}/confusion_matrices.pdf"
open_report "$CONFUSION_MATRIX_PATH" "confusion matrix"
