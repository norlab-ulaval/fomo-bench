import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

IS_MAPPING = os.getenv("IS_MAPPING")
STORAGE_PATH = os.getenv("STORAGE_PATH")
LIDAR_TYPE = "robosense"

if IS_MAPPING is None:
    print("IS_MAPPING is not set")
    exit(1)
elif STORAGE_PATH is None:
    print("STORAGE_PATH is not set")
    exit(1)

IS_MAPPING = IS_MAPPING == "1"
if IS_MAPPING:
    input_map_name = ""
    output_map_name = f"{STORAGE_PATH}/map.csv"
else:
    input_map_name = f"{STORAGE_PATH}/map.csv"
    output_map_name = ""


def generate_launch_description():
    ld = LaunchDescription()
    share_folder = get_package_share_directory("ros_launchers")

    kiss_icp_config = os.path.join(share_folder, "config", "_kiss-icp.yaml")

    ld.add_action(
        DeclareLaunchArgument(
            "use_sim_time", default_value="true", description="Use simulation time"
        )
    )

    if IS_MAPPING:
        kiss_slam_node = Node(
            package="kiss_slam_ros",
            executable="kiss_slam_node",
            name="kiss_slam_node",
            output="screen",
            parameters=[
                {
                    "points_topic": f"{LIDAR_TYPE}/points",
                    "use_sim_time": LaunchConfiguration("use_sim_time"),
                    "final_map_file_name": output_map_name,
                    "final_trajectory_file_name": f"{STORAGE_PATH}/trajectory.txt",
                    "final_logs_file_name": f"{STORAGE_PATH}/performance_results.log",
                }
            ],
        )
        ld.add_action(kiss_slam_node)
    else:
        kiss_slam_node = Node(
            package="kiss_slam_ros",
            executable="kiss_slam_node",
            name="kiss_slam_node",
            output="screen",
            sigterm_timeout="60",  # Wait 30 seconds before escalating to SIGTERM
            sigkill_timeout="10",  # Wait 5 more seconds before SIGKILL
            arguments=[
                "--ros-args",
                "--log-level",
                "debug",
                "--log-level",
                "rcl:=INFO",
                "--log-level",
                "rmw_fastrtps_cpp:=INFO",
                "--log-level",
                "rclcpp:=INFO",
            ],
            parameters=[
                {
                    "points_topic": f"{LIDAR_TYPE}/points",
                    "use_sim_time": LaunchConfiguration("use_sim_time"),
                    "initial_map_file_name": input_map_name,
                    "final_trajectory_file_name": f"{STORAGE_PATH}/trajectory.txt",
                },
                kiss_icp_config,
            ],
        )
        ld.add_action(kiss_slam_node)

    return ld
