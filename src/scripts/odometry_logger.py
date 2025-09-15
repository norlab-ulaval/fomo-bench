#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
import csv
import os
from nav_msgs.msg import Odometry

# --- Configuration ---
# The directory where the trajectory file will be saved.
# This path should be accessible from within your ROS container/environment.
OUTPUT_PATH_DIR = "/trajectory_files"
# The name of the output file. It can be set via an environment variable.
OUTPUT_FILE_NAME = os.getenv("OUTPUT_FILE_NAME", "estimated_trajectory.txt")
if len(OUTPUT_FILE_NAME) == 0:
    OUTPUT_FILE_NAME = "estimated_trajectory.txt"
# The full path to the output CSV file.
CSV_FILE = os.path.join(OUTPUT_PATH_DIR, OUTPUT_FILE_NAME)

class OdometryLogger(Node):
    """
    ROS2 Node to log odometry data in TUM format.
    """

    def __init__(self):
        super().__init__('odometry_logger')

        # --- Setup Directory and File ---
        # This section runs once when the node starts.
        try:
            # Ensure the output directory exists.
            os.makedirs(OUTPUT_PATH_DIR, exist_ok=True)
            self.get_logger().info(f"Output directory is set to: {OUTPUT_PATH_DIR}")

            # Create a new, empty file (or clear an existing one).
            # This ensures the node starts with a fresh log file every time.
            with open(CSV_FILE, "w") as f:
                pass  # This will create an empty file or truncate an existing one.
            self.get_logger().info(f"Successfully created/cleared trajectory file: {CSV_FILE}")
        except OSError as e:
            self.get_logger().error(f"Failed to create directory or file: {e}")
            # If we can't create the file/dir, there's no point in continuing.
            raise e

        # --- Subscribe to Topic ---
        # Subscribe to the /estimated_odom topic.
        # The 'odometry_callback' function will be executed for each message.
        self.subscription = self.create_subscription(
            Odometry,
            '/estimated_odom',
            self.odometry_callback,
            10  # QoS history depth
        )

        self.get_logger().info("Odometry logger started. Listening to /estimated_odom...")

        # Create throttled loggers for periodic messages
        self._last_log_time = self.get_clock().now()
        self._last_error_time = self.get_clock().now()

    def odometry_callback(self, msg):
        """
        Callback function to log odometry data in the TUM format.
        This function is called every time a new message is received on the /estimated_odom topic.
        """
        # Extract position
        x = msg.pose.pose.position.x
        y = msg.pose.pose.position.y
        z = msg.pose.pose.position.z

        # Extract orientation (in TUM format order: qx, qy, qz, qw)
        qx = msg.pose.pose.orientation.x
        qy = msg.pose.pose.orientation.y
        qz = msg.pose.pose.orientation.z
        qw = msg.pose.pose.orientation.w

        # Extract timestamp (convert from nanoseconds to seconds)
        timestamp = msg.header.stamp.sec + msg.header.stamp.nanosec * 1e-9

        # Append the pose to the file
        try:
            with open(CSV_FILE, "a") as f:
                # Use a space as a delimiter for the TUM format
                writer = csv.writer(f, delimiter=" ")
                # Write the data row: timestamp tx ty tz qx qy qz qw
                writer.writerow([timestamp, x, y, z, qx, qy, qz, qw])
        except IOError as e:
            # Throttled error logging (once per second)
            current_time = self.get_clock().now()
            if (current_time - self._last_error_time).nanoseconds / 1e9 >= 1.0:
                self.get_logger().error(f"Could not write to file {CSV_FILE}: {e}")
                self._last_error_time = current_time

        # Log the received data to the console (throttled to once every 10 seconds)
        current_time = self.get_clock().now()
        if (current_time - self._last_log_time).nanoseconds / 1e9 >= 10.0:
            self.get_logger().info(f"Logged odometry data to {CSV_FILE}")
            self._last_log_time = current_time

def main():
    """
    Initializes the ROS2 node and starts logging.
    """
    rclpy.init()

    try:
        odometry_logger = OdometryLogger()

        # Keep the node running until it's shut down (e.g., by Ctrl+C).
        rclpy.spin(odometry_logger)

    except Exception as e:
        print(f"Error in main: {e}")
    finally:
        # Clean shutdown
        if 'odometry_logger' in locals():
            odometry_logger.destroy_node()
        rclpy.shutdown()

if __name__ == "__main__":
    main()
