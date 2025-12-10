#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# Source ROS environment. roscore is guaranteed to be running by docker-compose.
source /opt/ros/humble/setup.bash

export BAG_PATH="/rosbag_file"
echo "Looking for bag(s) at: $BAG_PATH ($BAGFILES_PATH_HOST on host)"

# This variable will hold the file path(s) for rosbag play
BAG_FILES_TO_PLAY=""

# Check if the path is a file or a directory
if [ -f "$BAG_PATH" ]; then
    echo "Found a single bag file."
    BAG_FILES_TO_PLAY="$BAG_PATH"
    echo "Bag file information:"
    ls -lh "$BAG_FILES_TO_PLAY"
    ros2 bag info "$BAG_FILES_TO_PLAY"
elif [ -d "$BAG_PATH" ]; then
    echo "Found a directory. Looking for .mcap files inside..."
    # Check for .mcap files and count them
    BAG_COUNT=$(ls -1q "$BAG_PATH"/*.mcap 2>/dev/null | wc -l)
    if [ "$BAG_COUNT" -eq 0 ]; then
        echo "Error: Directory exists, but no .mcap files were found inside."
        exit 1
    fi
    echo "Found $BAG_COUNT bag files. They will be played together."
    # Use a glob pattern to play all bag files
    BAG_FILES_TO_PLAY="$BAG_PATH/*.mcap"
else
    echo "Error: Path not found (neither a file nor a directory): $BAG_PATH"
    exit 1
fi

# Check if topics file exists
if [ -f "/tmp/topics.txt" ]; then
    echo "Using topics file: /tmp/topics.txt"
    # topics file is list of topics separated by a new line, we want to make it a list of topics
    TOPICS=$(cat /tmp/topics.txt | tr '\n' ' ')

else
    echo "No topics file found. Using only basic topics."
fi
# Append basic topics to the list of topics
TOPICS=("${TOPICS[@]}" "/tf_static" "/vectornav/data_raw" "/xsens/data_raw" "/warthog/platform/odom")

# Start the rosbag play with a large read-ahead queue
# We need to start it paused to allow all data to be loaded before we can start the data processing
ROSBAG_PLAY_COMMAND="ros2 bag play ${BAG_FILES_TO_PLAY} --clock -r${ROSBAG_PLAY_RATE} --read-ahead-queue-size ${ROSBAG_READ_AHEAD_QUEUE_SIZE:-1000} -s mcap -p"
# if TOPICS is not empty, play only the topics in TOPICS
if [ -n "$TOPICS" ]; then
    echo "Playing only the topics in TOPICS..."
    ROSBAG_PLAY_COMMAND="$ROSBAG_PLAY_COMMAND --topics ${TOPICS[@]}"
fi

echo "Playing the bagfile..."
echo $ROSBAG_PLAY_COMMAND

# Start rosbag play in background
$ROSBAG_PLAY_COMMAND
ROSBAG_EXIT_CODE=$?

if [ $ROSBAG_EXIT_CODE -eq 0 ]; then
    echo "Played the bagfile. Exiting with success."
    exit 0
else
    echo "Error: Rosbag play failed with exit code $ROSBAG_EXIT_CODE"
    exit 1
fi

