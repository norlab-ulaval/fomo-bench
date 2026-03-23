#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common functions
source "${SCRIPT_DIR}/src/lib/pipeline_common.sh"

if [ -d ".venv" ]; then
    source .venv/bin/activate
fi


# --- Main Pipeline ---
# Initialize pipeline and load environment
init_pipeline

# Prepare output directory
prepare_output_directory

missing_combinations=()
mapfile -t missing_combinations < <(get_missing_evaluations)

# First execute the diagonal (all mapping runs)
for map_folder in "${TARGET_DEPLOYMENTS[@]}"; do
    if [[ ! " ${missing_combinations[*]} " =~ " ${map_folder}_${map_folder} " ]]; then
        info "Skipping already evaluated diagonal for $map_folder"
        continue
    fi

    traj_row_path=$(get_trajectory_rosbag "$map_folder" "$TARGET_TRAJECTORY_NAME" | tail -n 1)
    # Check if input directory exists
    if [ ! -d "$traj_row_path" ]; then
        warn "Warning: Bag directory ${traj_row_path} does not exist, skipping..."
        continue
    fi

    traj_row=$(basename $traj_row_path)
    info "$map_folder: generating diagonal for $traj_row_path : $traj_row"

    if ! eval_single_trajectory "$traj_row_path" "$traj_row" "$traj_row"; then
        warn "Evaluation failed for $traj_row. Skipping..."
        continue
    fi
    sleep 2
done

# Then execute the off-diagonal (all localization runs) column after column to minimize data copy
# for combo in "${missing_combinations[@]}"; do
#     IFS="_" read -r map_folder loc_folder <<< "$combo"
#     # skip the diagonal as we already evaluated it
#     if [ "$map_folder" == "$loc_folder" ]; then
#         continue
#     fi

#     traj_col_path=$(get_trajectory_rosbag "$loc_folder" "$TARGET_TRAJECTORY_NAME")
#     if [ ! -d "$traj_col_path" ]; then
#         warn "Warning: Col directory $traj_col_path does not exist, skipping..."
#         continue
#     fi
#     traj_col=$(basename $traj_col_path)

#     traj_row_path=$(generate_trajectory_path "$BASE_PATH_REMOTE/ijrr" "$map_folder" "$TARGET_TRAJECTORY_NAME")
#     if [ ! -d "$traj_row_path" ]; then
#         warn "Warning: Row directory $traj_row_path does not exist, skipping..."
#         continue
#     fi
#     traj_row=$(basename $traj_row_path)

#     info "Running evaluation for $traj_col_path : col: $traj_col row: $traj_row"
#     if ! eval_single_trajectory "$traj_col_path" "$traj_row" "$traj_col"; then
#         warn "Evaluation failed for query $traj_col on map $traj_row. Skipping..."
#         continue
#     fi
#     sleep 2
# done

# info "Creating confusion matrix..."
# $DOCKER_COMPOSE_CMD up plot_confusion_matrix
# success "Confusion matrix created."

# CONFUSION_MATRIX_PATH="${OUTPUT_PATH_HOST}/confusion_matrices.pdf"
# open_report "$CONFUSION_MATRIX_PATH" "confusion matrix"
