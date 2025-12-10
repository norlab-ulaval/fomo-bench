import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

IS_MAPPING = os.getenv("IS_MAPPING") == "1"
STORAGE_PATH = os.getenv("STORAGE_PATH")
OUTPUT_NAMESPACE = os.getenv("OUTPUT_NAMESPACE")
IMU_TYPE = "vectornav"  # or 'xsens'

if IS_MAPPING is None:
    print("IS_MAPPING is not set")
    exit(1)
elif STORAGE_PATH is None:
    print("STORAGE_PATH is not set")
    exit(1)

map_name = os.path.join(STORAGE_PATH, "orb_slam3_atlas")


def generate_launch_description():
    ld = LaunchDescription()
    share_folder = get_package_share_directory("ros_launchers")
    orbslam3_share_folder = get_package_share_directory("orbslam3")
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

    default_config_file = os.path.join(
        orbslam3_share_folder,
        "config",
        "stereo-inertial",
        "zedx.yaml",
    )
    temp_config_file = os.path.join(
        orbslam3_share_folder,
        "config",
        "stereo-inertial",
        "temp.yaml",
    )
    print("Updating configuration file")
    print(f"Copying default from {default_config_file} to {temp_config_file}")
    with open(default_config_file, "r") as fin, open(temp_config_file, "w") as fout:
        lines = fin.readlines()
        for line in lines:
            fout.write(line)
            if line.startswith("Atlas"):
                if IS_MAPPING:
                    print("Will save atlas to ", map_name)
                    fout.write(f"System.SaveAtlasToFile: {map_name}\n")
                else:
                    print("Will load atlas from ", map_name)
                    fout.write(f"System.LoadAtlasFromFile: {map_name}\n")
                    fout.write("System.LocalizationMode: True\n")

    orbslam3_node = Node(
        package="orbslam3",
        executable="stereo-inertial",
        name="orbslam3_stereo",
        output="screen",
        sigterm_timeout="60",  # Wait 30 seconds before escalating to SIGTERM
        sigkill_timeout="10",  # Wait 5 more seconds before SIGKILL
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
                "rectify": False,
                "output_folder": STORAGE_PATH,
                "vocabulary": os.path.join(
                    orbslam3_share_folder,
                    "vocabulary",
                    "ORBvoc.txt",
                ),
                "config": temp_config_file,
            }
        ],
        remappings=[
            ("camera_pose", f"{OUTPUT_NAMESPACE}/estimated_pose"),
            ("image_left", "zedx/left/image_rect"),
            ("image_right", "zedx/right/image_rect"),
            ("imu", f"{IMU_TYPE}/data"),
        ],
    )
    ld.add_action(orbslam3_node)
    return ld
