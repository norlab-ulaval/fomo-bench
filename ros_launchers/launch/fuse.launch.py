from launch import LaunchDescription
from launch_ros.actions import Node
from ament_index_python.packages import get_package_share_directory
import os
from launch.actions import IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource

NAMESPACE = os.getenv("NAMESPACE")


def generate_launch_description():
    share_dir = get_package_share_directory("ros_launchers")

    # Odometry covariance injector
    odom_cov_injector = Node(
        executable="python3",
        arguments=[
            os.path.join("/ros2_ws", "src", "fuse", "odom_covariance_injector.py")
        ],
        name="odom_covariance_injector",
        output="screen",
        parameters=[
            {"use_sim_time": True},
            {"input_topic": "/warthog/platform/odom"},
            {"output_topic": "/warthog/platform/odom_with_cov"},
            {"twist_cov_vx": 0.5},
            {"twist_cov_vyaw": 0.1},
        ],
    )

    # Fuse node
    fuse_node = Node(
        package="fuse_optimizers",
        executable="fixed_lag_smoother_node",
        name="fuse_node",
        output="screen",
        remappings=[
            ("odom_filtered", f"{NAMESPACE}/estimated_odom"),
            ("vectornav/data", f"{NAMESPACE}/vectornav/data_unbiased"),
        ],
        parameters=[
            os.path.join(share_dir, "config", "_fuse.yaml"),
            {"use_sim_time": True},
        ],
    )

    imu_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            [os.path.join(share_dir, "launch", "imu.launch.py")]
        )
    )

    return LaunchDescription(
        [
            imu_launch,
            odom_cov_injector,
            fuse_node,
        ]
    )
