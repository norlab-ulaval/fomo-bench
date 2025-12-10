#!/bin/bash
echo "Starting trajectory analysis..."

# The shell finds 'scripts/trajectory_analysis.py' because we are in '/app'.
COMMAND="python3 scripts/trajectory_analysis.py --zero --alignment kabsch"

if [ -n "$MAPPING_DATE" ]; then
    COMMAND="$COMMAND --mapping_date $MAPPING_DATE"
fi

if [ -n "$LOCALIZATION_DATE" ]; then
    COMMAND="$COMMAND --localization_date $LOCALIZATION_DATE"
fi

if [ -n "$SLAM_NAME" ]; then
    COMMAND="$COMMAND --slam $SLAM_NAME"
fi

echo "Running command: $COMMAND"
$COMMAND
