#!/bin/bash

input_path_host=/mnt/ssd/fomo-radar


process_trajectory() {
    local trajectory=$1
    local output_path_host="/home/nicolas-lauzon/offline-navtechradarslam/${trajectory}"

    for date_dir in "${input_path_host}"/*/; do
        date=$(basename "${date_dir}")
        for dataset_dir in "${date_dir}${trajectory}_"*/; do
            [ -d "${dataset_dir}" ] || continue
            dataset=$(basename "${dataset_dir}")
            echo $dataset
            mkdir -p "${output_path_host}/${date}/${dataset}"
            echo "Processing dataset ${date}/${dataset}"

            log_file="${output_path_host}/${date}/${dataset}/output.log"
            echo "START_TIME: $(date +%s)" > "$log_file"

            docker run -it \
                    --name navtechradarslam \
                    -it \
                    --rm \
                    --cpus "10" \
                    --privileged \
                    --network host \
                    -e SSH_AUTH_SOCK=${SSH_AUTH_SOCK} \
                    -v "${dataset_dir}":/data \
                    -v "${output_path_host}/${date}/${dataset}":/output \
                    -v "${dataset_dir}/calib":/calib \
                    -v "./ros_launchers":"/ros2_ws/src/ros_launchers" \
					-v ".":"/fomo-bench" \
                    -e NAMESPACE="" \
                    -e IS_MAPPING=1 \
                    -e STORAGE_PATH=/output \
                    kaist/navtechradarslam /bin/bash -c "source /opt/ros/humble/setup.bash && source /ros2_ws/install/setup.bash && ros2 launch ros_launchers navtechRadarSlam.launch.py bag_file:=/data" \
                    2>&1 | tee "${output_path_host}/${date}/${dataset}/docker.log"
            echo "END_TIME: $(date +%s)" >> "$log_file"
        done
    done
}

# process_trajectory "blue"
# process_trajectory "yellow"
# process_trajectory "green"
# process_trajectory "magenta"
process_trajectory "red" # red is not complete

# input_path_host=/media/mabox/SSD_Matej/fomo-lidar
# process_trajectory "orange" # red is processed on gab-server