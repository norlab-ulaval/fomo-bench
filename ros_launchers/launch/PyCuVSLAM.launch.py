import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import ComposableNodeContainer
from launch_ros.descriptions import ComposableNode

IS_MAPPING = os.getenv("IS_MAPPING") == "1"
STORAGE_PATH = os.getenv("STORAGE_PATH")
IMU_TYPE = "vectornav"  # or 'xsens'

if IS_MAPPING is None:
    print("IS_MAPPING is not set")
    exit(1)
elif STORAGE_PATH is None:
    print("STORAGE_PATH is not set")
    exit(1)

if IS_MAPPING:
    input_map_name = ""
    output_map_name = STORAGE_PATH
else:
    input_map_name = STORAGE_PATH
    output_map_name = ""


def generate_launch_description() -> LaunchDescription:
    ld = LaunchDescription()

    share_folder = get_package_share_directory("ros_launchers")
    default_params_file = os.path.join(
        share_folder,
        "config",
        "_pycuvslam.yaml",
    )

    params_file_arg = DeclareLaunchArgument(
        "params_file",
        default_value=default_params_file,
        description="Path to the YAML file with parameters for VisualSlamNode",
    )

    launch_folder = os.path.join(share_folder, "launch")

    ld.add_action(
        DeclareLaunchArgument(
            "use_sim_time", default_value="true", description="Use simulation time"
        )
    )

    imu_launch = IncludeLaunchDescription(
        PythonLaunchDescriptionSource([os.path.join(launch_folder, "imu.launch.py")])
    )
    ld.add_action(imu_launch)

    # Image proc node for left camera
    image_proc_left = ComposableNode(
        package="image_proc",
        plugin="image_proc::DebayerNode",
        name="image_proc_left",
        namespace="camera_left",
        remappings=[
            ("image_raw", "/zedx/left/image_rect"),
            ("image_mono", "/zedx/left/image_rect_mono"),
        ],
    )

    # Image proc node for right camera
    image_proc_right = ComposableNode(
        package="image_proc",
        plugin="image_proc::DebayerNode",
        name="image_proc_right",
        namespace="camera_right",
        remappings=[
            ("image_raw", "/zedx/right/image_rect"),
            ("image_mono", "/zedx/right/image_rect_mono"),
        ],
    )

    visual_slam_node = ComposableNode(
        name="visual_slam_node",
        package="isaac_ros_visual_slam",
        plugin="nvidia::isaac_ros::visual_slam::VisualSlamNode",
        parameters=[
            LaunchConfiguration("params_file"),
            {
                "save_map_folder_path": output_map_name,
                "load_map_folder_path": input_map_name,
                "localize_on_startup": not IS_MAPPING,
            },
        ],
        remappings=[
            ("/visual_slam/image_0", "/zedx/left/image_rect_mono"),
            ("/visual_slam/camera_info_0", "/zedx/left/camera_info"),
            ("/visual_slam/image_1", "/zedx/right/image_rect_mono"),
            ("/visual_slam/camera_info_1", "/zedx/right/camera_info"),
            ("/visual_slam/imu", f"/{IMU_TYPE}/data_unbiased"),
        ],
    )

    container = ComposableNodeContainer(
        name="visual_slam_launch_container",
        namespace="",
        package="rclcpp_components",
        executable="component_container",
        composable_node_descriptions=[
            image_proc_left,
            image_proc_right,
            visual_slam_node,
        ],
        sigterm_timeout="30",  # Wait 30 seconds before escalating to SIGTERM
        sigkill_timeout="5",  # Wait 5 more seconds before SIGKILL
        output="both",
        arguments=[
            "--ros-args",
            "--log-level",
            "info",
            "--log-level",
            "rcl:=INFO",
            "--log-level",
            "rmw_fastrtps_cpp:=INFO",
            "--log-level",
            "rclcpp:=INFO",
        ],
        parameters=[
            {
                "use_sim_time": LaunchConfiguration("use_sim_time"),
            }
        ],
    )

    ld.add_action(params_file_arg)
    ld.add_action(container)

    return ld
