#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common functions
source "${SCRIPT_DIR}/src/lib/pipeline_common.sh"

if [ -d ".venv" ]; then
    source .venv/bin/activate
fi

# --- Cross-Season Evaluation Configuration ---
# Mapping deployments (rows in confusion matrix)
MAPPING_DEPLOYMENTS=(
    "2025-01-29"
    "2025-06-26"
    "2025-10-14"
)

# Localization deployments (columns in confusion matrix)
LOCALIZATION_DEPLOYMENTS=(
    "2025-03-10"
    "2025-08-20"
    "2024-11-21"
)

# --- Main Pipeline ---
# Initialize pipeline and load environment
init_pipeline

# Prepare output directory
prepare_output_directory

info "Starting cross-season evaluation: ${#MAPPING_DEPLOYMENTS[@]} mapping × ${#LOCALIZATION_DEPLOYMENTS[@]} localization = $((${#MAPPING_DEPLOYMENTS[@]} * ${#LOCALIZATION_DEPLOYMENTS[@]})) combinations"
info "Mapping deployments (rows): ${MAPPING_DEPLOYMENTS[*]}"
info "Localization deployments (cols): ${LOCALIZATION_DEPLOYMENTS[*]}"

# Execute the off-diagonal evaluations
# Process column by column to minimize data copy
for loc_folder in "${LOCALIZATION_DEPLOYMENTS[@]}"; do
    traj_col_path=$(get_trajectory_rosbag "$loc_folder" "$TARGET_TRAJECTORY_NAME")
    if [ ! -d "$traj_col_path" ]; then
        warn "Warning: Col directory $traj_col_path does not exist, skipping..."
        continue
    fi
    traj_col=$(basename $traj_col_path)
	
	for map_folder in "${MAPPING_DEPLOYMENTS[@]}"; do
		traj_row_path=$(generate_trajectory_path "$BASE_PATH_REMOTE/ijrr" "$map_folder" "$TARGET_TRAJECTORY_NAME")
		if [ ! -d "$traj_row_path" ]; then
			warn "Warning: Row directory $traj_row_path does not exist, skipping..."
			continue
		fi
		traj_row=$(basename $traj_row_path)

		info "Running evaluation for $traj_col_path : col: $traj_col row: $traj_row"
		if ! eval_single_trajectory "$traj_col_path" "$traj_row" "$traj_col"; then
			warn "Evaluation failed for query $traj_col on map $traj_row. Skipping..."
			continue
		fi
		sleep 2
    done
done

success "Cross-season evaluation completed!"
info "Total combinations processed: $((${#MAPPING_DEPLOYMENTS[@]} * ${#LOCALIZATION_DEPLOYMENTS[@]}))"

# Optionally create confusion matrix
# info "Creating confusion matrix..."
# $DOCKER_COMPOSE_CMD up plot_confusion_matrix
# success "Confusion matrix created."

# CONFUSION_MATRIX_PATH="${OUTPUT_PATH_HOST}/confusion_matrices.pdf"
# open_report "$CONFUSION_MATRIX_PATH" "confusion matrix"
