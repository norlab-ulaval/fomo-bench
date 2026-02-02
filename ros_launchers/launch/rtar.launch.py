import json
import os
import os.path as osp

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node

NAMESPACE = os.getenv("NAMESPACE")


def generate_launch_description():
    # config directory
    config_dir = osp.join(get_package_share_directory("fomo_rtr_wrapper"), "config")

    commonNodeArgs = {
        "package": "vtr_navigation",
        "namespace": "vtr",
        "executable": "vtr_navigation",
        "output": "screen",
        "sigterm_timeout": "60",  # Wait 60 seconds before escalating to SIGTERM
        "sigkill_timeout": "10",  # Wait 10 more seconds before SIGKILL
    }

    INPUT_IMU_BIAS_FILE = os.path.join("/", "calib", "imu.json")
    IMU_TYPE = os.getenv("IMU_TYPE", "vectornav")  # or 'xsens'

    bias_z = 0.0
    if os.path.exists(INPUT_IMU_BIAS_FILE):
        with open(INPUT_IMU_BIAS_FILE, "r") as f:
            bias_data = json.load(f)
            bias_z = bias_data[IMU_TYPE]["angular_velocity"]["z"]
    print(f"Setting bias to {bias_z}")

    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "base_params",
                description="base parameter file (sensor, robot specific)",
            ),
            Node(
                **commonNodeArgs,
                parameters=[
                    PathJoinSubstitution(
                        (config_dir, LaunchConfiguration("base_params"))
                    ),
                    {
                        "data_dir": "/data",
                        "model_dir": "/data/models",
                        "start_new_graph": int(os.getenv("IS_MAPPING")) == 1,
                        "use_sim_time": True,
                        "path_planning.type": "stationary",
                        "gyro_bias.z": bias_z,
                        "log_debug": False,
                        "robot_frame": "base_link",
                        "radar_frame": "navtech",
                        "radar_topic": "/navtech/b_scan_msg",
                        "gyro_frame": IMU_TYPE,
                        "gyro_topic": f"/{IMU_TYPE}/data_raw",
                        "log_enabled": [
                            "mission.state_machine",
                            "pose_graph",
                        ],
                    },
                ],
                remappings=[
                    ("odometry", "estimated_odom"),
                    ("/tf", "tf"),
                ],
            ),
            Node(
                package="fomo_rtr_wrapper",
                namespace=NAMESPACE,
                executable="start_rtr_fomo",
                output="screen",
            ),
        ]
    )
