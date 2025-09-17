#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# Source ROS environment. roscore is guaranteed to be running by docker-compose.
source /opt/ros/humble/setup.bash

# Execute the command passed to this script (e.g., ros2 run or "ros2 launch")
# The 'exec' command replaces the shell process with the given command,
# which is important for proper signal handling (like Ctrl+C).
exec "$@"
