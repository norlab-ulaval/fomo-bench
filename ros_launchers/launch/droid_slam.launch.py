from launch import LaunchDescription
from launch_ros.actions import Node
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from ament_index_python.packages import get_package_share_directory
import os

def generate_launch_description():
    pkg_share = get_package_share_directory('ros_launchers')
    droid_slam_ros_share = get_package_share_directory('droid_slam_ros')
    
    # Default weights path
    default_weights = os.path.join(droid_slam_ros_share, 'droid.pth')

    # Config file
    config_file = os.path.join(pkg_share, 'config', '_droid_slam.yaml')

    return LaunchDescription([
        # Keep weights argument for easy override
        DeclareLaunchArgument('weights', default_value=default_weights, description='Path to model weights'),
        DeclareLaunchArgument('use_sim_time', default_value='true', description='Use simulation time'),

        Node(
            package='droid_slam_ros',
            executable='ros_node.py',
            name='droid_node',
            namespace=os.getenv('NAMESPACE'),
            output="screen",
            sigterm_timeout="240",  # Wait before escalating to SIGTERM
            sigkill_timeout="10",  # Wait before SIGKILL
            parameters=[
                config_file,
                {
                "use_sim_time": LaunchConfiguration("use_sim_time"),
                'storage_path': os.getenv('STORAGE_PATH'),
                'weights': LaunchConfiguration('weights'), # Override weights from launch arg
                'stereo': True} # Enforce stereo
            ]
        )
    ])
