import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.conditions import IfCondition
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

NAMESPACE = os.getenv("NAMESPACE")
IS_MAPPING = os.getenv("IS_MAPPING")
STORAGE_PATH = os.getenv("STORAGE_PATH")


def generate_launch_description():
    pkg_orora = get_package_share_directory("orora")

    do_slam_arg = DeclareLaunchArgument(
        "do_slam", default_value="true", description="Enable SLAM"
    )
    algorithm_arg = DeclareLaunchArgument(
        "algorithm", default_value="ORORA", description="Algorithm to use"
    )
    dataset_arg = DeclareLaunchArgument(
        "dataset", default_value="fomo", description="Dataset to use"
    )
    sim_time_arg = DeclareLaunchArgument(
        "use_sim_time", default_value="true", description="Use sim time"
    )

    # Configuration
    orora_params_file = os.path.join(pkg_orora, "config", "orora_params.yaml")

    # Nodes
    orora_node = Node(
        package="orora",
        namespace=NAMESPACE,
        executable="orora_odom",
        name="orora_odom",
        output="screen",
        sigterm_timeout="60",  # Wait 60 seconds before escalating to SIGTERM
        sigkill_timeout="10",  # Wait 5 more seconds before SIGKILL
        parameters=[
            orora_params_file,
            {
                "keypoint_extraction": "cen2018",
                "algorithm": LaunchConfiguration("algorithm"),
                "dataset": LaunchConfiguration("dataset"),
                "viz_extraction": False,
                "viz_matching": False,
                "frame_rate": 4.0,
                "stop_each_frame": False,
                "use_sim_time": LaunchConfiguration("use_sim_time"),
            },
        ],
    )

    sc_pgo_node = Node(
        package="sc_pgo",
        executable="alaserPGO",
        namespace=NAMESPACE,
        name="loop_closure",
        output="screen",
        sigterm_timeout="120",  # Wait 120 seconds before escalating to SIGTERM
        sigkill_timeout="10",  # Wait 5 more seconds before SIGKILL
        parameters=[
            {
                "keyframe_meter_gap": 0.2,
                "sc_dist_thres": 0.45,
                "use_sim_time": LaunchConfiguration("use_sim_time"),
                "pcd_save_dir": STORAGE_PATH,
                "loop_fitness_score_threshold": 14.0,
            }
        ],
        condition=IfCondition(LaunchConfiguration("do_slam")),
    )

    return LaunchDescription(
        [do_slam_arg, sim_time_arg, algorithm_arg, dataset_arg, orora_node, sc_pgo_node]
    )
