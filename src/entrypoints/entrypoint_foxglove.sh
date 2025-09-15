#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# Source ROS environment. roscore is guaranteed to be running by docker-compose.
source /opt/ros/humble/setup.bash

echo "Starting foxglove server..."

ros2 launch foxglove_bridge foxglove_bridge_launch.xml send_buffer_limit:=1000000000 port:=8772
