#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the common functions
source "${SCRIPT_DIR}/src/lib/pipeline_common.sh"

# --- Seasons-specific Functions ---

generate_trajectory_path() {
    local base_path=$1
    local deployment_folder=$2
    local trajectory_name=$3
    current_folder=$(pwd)
    deployment_path=$base_path/${deployment_folder}
    if [ ! -d "$deployment_path" ]; then
        return 0
    fi
    cd $deployment_path
    local folder=$(ls -d $trajectory_name* 2>/dev/null | head -n 1)
    cd $current_folder

    if [[ -n "${folder}" ]]; then
        echo "${base_path}/${deployment_folder}/${folder}"
    fi
}

verify_free_space() {
    local remote_path=$1
    local local_path=$2
    local remote_size=$(du -hs $remote_path | cut -f1)
    local free_space=$(df -h $local_path | awk 'NR==2 {print $4}')
    info "Remote path: $remote_path size: $remote_size, Host free space: $free_space"

    # remove 'G' from remote_size and free_space
    remote_size=$(echo $remote_size | cut -d 'G' -f 1)
    free_space=$(echo $free_space | cut -d 'G' -f 1)

    if [[ $remote_size -gt $free_space ]]; then
        warn "Not enough space on the host to copy the remote folder. Remote size: $remote_size, Host free space: $free_space"
        warn "Waiting for user to free up space. Press enter when done..."
        read -p "Press enter when done..."
    fi
}

# Function to generate trajectory rosbag
# First check if the bag is already present on the host
# If not, verify if it is available on the remote
# If not, generate it on the host and copy it to the remote
get_trajectory_rosbag() {
    local deployment_folder=$1
    local trajectory_name=$2
    local trajectory_folder_host=""
    if [[ $RUN_SLAM -eq 1 ]]; then
        # check if the trajectory mcap is already present on the host
        trajectory_folder_host=$(generate_trajectory_path "$BASE_PATH_HOST" "$deployment_folder" "$trajectory_name")
        if [ -d "$trajectory_folder_host" ]; then
            echo $trajectory_folder_host
            return 0
        fi
        warn "No $trajectory_name trajectory folder found for deployment: $deployment_folder in: $BASE_PATH_HOST"

        # check if the trajectory mcap is already present on the remote
        local trajectory_folder_remote
        trajectory_folder_remote=$(generate_trajectory_path "$BASE_PATH_REMOTE"/mcap "$deployment_folder" "$trajectory_name")
        if [ -d "$trajectory_folder_remote" ]; then
            # verify that there is enough space on the host
            trajectory_destination_host="$BASE_PATH_HOST/$deployment_folder/"
            verify_free_space $trajectory_folder_remote $HOME

            info "Copying trajectory folder from $trajectory_folder_remote to $trajectory_destination_host"
            # copy the trajectory folder to the host
            rsync -rP $trajectory_folder_remote $trajectory_destination_host

            # return the local trajectory folder path
            echo "$trajectory_destination_host/$(basename $trajectory_folder_remote)"
            return 0
        fi
        warn "No $trajectory_name trajectory folder found for deployment: $deployment_folder in: $BASE_PATH_REMOTE/mcap"

        # check if the trajectory plaintext is on the remote
        local human_readable_folder_remote
        human_readable_folder_remote=$(generate_trajectory_path "$BASE_PATH_REMOTE"/ijrr "$deployment_folder" "$trajectory_name")
        if [ ! -d "$human_readable_folder_remote" ]; then
            error "No plaintext remote trajectory folder found for deployment: $deployment_folder and trajectory: $trajectory_name"
            return 0
        fi
        info "Generating trajectory rosbag for deployment: $deployment_folder and trajectory: $trajectory_name"
        trajectory_folder_host="$BASE_PATH_HOST/$deployment_folder/$(basename $human_readable_folder_remote)"
        trajectory_destination_remote="$BASE_PATH_REMOTE/mcap/$deployment_folder/"

        # verify that there is enough space on the host
        verify_free_space $human_readable_folder_remote $HOME
        mkdir -p $trajectory_folder_host

        info "Converting plaintext trajectory to mcap"
        docker run --rm -t \
            -v $human_readable_folder_remote:/input \
            -v $trajectory_folder_host:/output \
            ghcr.io/norlab-ulaval/fomo-sdk:latest ijrr_to_mcap \
            --input /input --output /output \
            --sensors navtech --sensors robosense \
            --sensors zedx_right --sensors zedx_left \
            --compress

        # copy calibration files and ground truth data
        info "Copying calibration files and ground truth data"
        cp -r $human_readable_folder_remote/calib $trajectory_folder_host
        cp $human_readable_folder_remote/gt.txt $trajectory_folder_host

        # copy the exported folder back to remote
        info "Copying trajectory folder back to remote"
        rsync -rP $trajectory_folder_host $trajectory_destination_remote
    else
        local human_readable_folder_remote
        human_readable_folder_remote=$(generate_trajectory_path "$BASE_PATH_REMOTE"/ijrr "$deployment_folder" "$trajectory_name")
        if [ ! -d "$human_readable_folder_remote" ]; then
            error "No plaintext remote trajectory folder found for deployment: $deployment_folder and trajectory: $trajectory_name"
            return 0
        fi
        trajectory_folder_host="$BASE_PATH_HOST/$deployment_folder/$(basename $human_readable_folder_remote)"
    fi

    sync # Wait for all pending writes to complete
    echo $trajectory_folder_host
    return 0
}


# --- Main Pipeline ---
if [ "${1}" != "--source-only" ]; then
    # Initialize pipeline and load environment
    init_pipeline

    # Prepare output directory
    prepare_output_directory

    # Run cross-seasonal evaluation
    ROW_FOLDERS=("${TARGET_DEPLOYMENTS[@]}")
    COL_FOLDERS=("${TARGET_DEPLOYMENTS[@]}")

    # First execute the diagonal (all mapping runs)
    for map_folder in "${ROW_FOLDERS[@]}"; do
        traj_row_path=$(get_trajectory_rosbag "$map_folder" "$TARGET_TRAJECTORY_NAME")
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
    for loc_folder in "${COL_FOLDERS[@]}"; do
        for map_folder in "${ROW_FOLDERS[@]}"; do
            # skip the diagonal as we already evaluated it
            if [ "$map_folder" == "$loc_folder" ]; then
                continue
            fi

            traj_col_path=$(get_trajectory_rosbag "$loc_folder" "$TARGET_TRAJECTORY_NAME")
            if [ ! -d "$traj_col_path" ]; then
                warn "Warning: Col directory $traj_col_path does not exist, skipping..."
                continue
            fi
            traj_col=$(basename $traj_col_path)

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

    # Create and open confusion matrix
    info "Creating confusion matrix..."
    $DOCKER_COMPOSE_CMD up plot_confusion_matrix
    success "Confusion matrix created."

    CONFUSION_MATRIX_PATH="${OUTPUT_PATH_HOST}/confusion_matrices.pdf"
    open_report "$CONFUSION_MATRIX_PATH" "confusion matrix"
fi
