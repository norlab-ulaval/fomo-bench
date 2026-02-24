#!/usr/bin/env python3
import csv
import os

import rclpy
from geometry_msgs.msg import Pose, PoseStamped, PoseWithCovarianceStamped
from nav_msgs.msg import Odometry
from rclpy.node import Node
from std_msgs.msg import Header

# --- Configuration ---
# The directory where the trajectory file will be saved.
# This path should be accessible from within your ROS container/environment.
OUTPUT_PATH_DIR = "/output"
# The name of the output file. It can be set via an environment variable.
OUTPUT_FILE_NAME = os.getenv("OUTPUT_FILE_NAME", "estimated_trajectory.txt")
if len(OUTPUT_FILE_NAME) == 0:
    OUTPUT_FILE_NAME = "estimated_trajectory.txt"
# The full path to the output CSV file.
OUTPUT_FILE = os.path.join(OUTPUT_PATH_DIR, OUTPUT_FILE_NAME)


class OdometryLogger(Node):
    """
    ROS2 Node to log odometry data in TUM format.
    """

    def __init__(self):
        namespace = os.getenv("NAMESPACE", "")
        node_name = "odometry_logger"

        if not len(namespace) == 0:
            node_name = f"{namespace}_{node_name}"
            namespace = "/" + namespace

        super().__init__(node_name)
        self.get_logger().info(f"Namespace is set to: {namespace}")
        # --- Setup Directory and File ---
        # This section runs once when the node starts.
        try:
            # Ensure the output directory exists.
            os.makedirs(OUTPUT_PATH_DIR, exist_ok=True)
            self.get_logger().info(f"Output directory is set to: {OUTPUT_PATH_DIR}")

            # Create a new, empty file (or clear an existing one).
            # This ensures the node starts with a fresh log file every time.
            with open(OUTPUT_FILE, "w") as _:
                pass  # This will create an empty file or truncate an existing one.
            self.get_logger().info(
                f"Successfully created/cleared trajectory file: {OUTPUT_FILE}"
            )
        except OSError as e:
            self.get_logger().error(f"Failed to create directory or file: {e}")
            # If we can't create the file/dir, there's no point in continuing.
            raise e

        self.active_function = None

        # --- Subscribe to Topic ---
        # Subscribe to the /estimated_odom topic.
        # The 'odometry_callback' function will be executed for each message.
        self.subscription = self.create_subscription(
            Odometry,
            f"{namespace}/estimated_odom",
            self.odometry_callback,
            10,  # QoS history depth
        )
        # --- Subscribe to Topic ---
        # Subscribe to the /estimated_pose topic.
        # The 'pose_callback' function will be executed for each message.
        self.subscription = self.create_subscription(
            PoseWithCovarianceStamped,
            f"{namespace}/estimated_pose_with_covariance",
            self.pose_with_covariance_callback,
            10,  # QoS history depth
        )
        self.subscription = self.create_subscription(
            PoseStamped,
            f"{namespace}/estimated_pose",
            self.pose_callback,
            10,  # QoS history depth
        )

        self.get_logger().info(
            f"Odometry logger started. Listening to {namespace}/estimated_odom and {namespace}/estimated_pose..."
        )

        # Create throttled loggers for periodic messages
        self._last_log_time = self.get_clock().now()
        self._last_error_time = self.get_clock().now()

    def write_pose(self, pose: Pose, header: Header):
        """
        Function to log pose data in the TUM format.
        This function is called every time a new message is received on the /estimated_odom or /estimated_pose_stamped topic.
        """
        # Extract position
        x = pose.position.x
        y = pose.position.y
        z = pose.position.z

        # Extract orientation (in TUM format order: qx, qy, qz, qw)
        qx = pose.orientation.x
        qy = pose.orientation.y
        qz = pose.orientation.z
        qw = pose.orientation.w

        # Extract timestamp (convert from nanoseconds to seconds)
        timestamp = header.stamp.sec + header.stamp.nanosec * 1e-9

        # Append the pose to the file
        try:
            with open(OUTPUT_FILE, "a") as f:
                # Use a space as a delimiter for the TUM format
                writer = csv.writer(f, delimiter=" ")
                # Write the data row: timestamp tx ty tz qx qy qz qw
                writer.writerow([timestamp, x, y, z, qx, qy, qz, qw])
        except IOError as e:
            # Throttled error logging (once per second)
            current_time = self.get_clock().now()
            if (current_time - self._last_error_time).nanoseconds / 1e9 >= 1.0:
                self.get_logger().error(f"Could not write to file {OUTPUT_FILE}: {e}")
                self._last_error_time = current_time

        # Log the received data to the console (throttled to once every 10 seconds)
        current_time = self.get_clock().now()
        if (current_time - self._last_log_time).nanoseconds / 1e9 >= 10.0:
            self.get_logger().info(f"Logged odometry data to {OUTPUT_FILE}")
            self._last_log_time = current_time

    def odometry_callback(self, msg: Odometry):
        """
        This function is called every time a new message is received on the /estimated_odom topic.
        """
        if self.active_function is None:
            self.active_function = self.odometry_callback
        elif self.active_function != self.odometry_callback:
            self.get_logger().warn(
                f"Already logging data using {self.active_function.__qualname__} callback. Skipping."
            )
            return
        self.write_pose(msg.pose.pose, msg.header)

    def pose_callback(self, msg: PoseStamped):
        """
        This function is called every time a new message is received on the /estimated_pose topic.
        """
        if self.active_function is None:
            self.active_function = self.pose_callback
        elif self.active_function != self.pose_callback:
            self.get_logger().warn(
                f"Already logging data using {self.active_function.__qualname__} callback. Skipping."
            )
            return
        self.write_pose(msg.pose, msg.header)

    def pose_with_covariance_callback(self, msg: PoseWithCovarianceStamped):
        """
        This function is called every time a new message is received on the /estimated_pose_with_covariance topic.
        """
        if self.active_function is None:
            self.active_function = self.pose_with_covariance_callback
        elif self.active_function != self.pose_with_covariance_callback:
            self.get_logger().warn(
                f"Already logging data using {self.active_function.__qualname__} callback. Skipping."
            )
            return
        self.write_pose(msg.pose.pose, msg.header)


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
        if "odometry_logger" in locals():
            odometry_logger.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
