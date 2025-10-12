#!/bin/bash
echo "Starting trajectory analysis..."

# The shell finds 'scripts/plot_confusion_matrix.py' because we are in '/app'.
COMMAND="python3 scripts/plot_confusion_matrix.py"

if [ -n "$SLAM_NAME" ]; then
    COMMAND="$COMMAND --slam $SLAM_NAME"
fi

echo "Running command: $COMMAND"
$COMMAND
