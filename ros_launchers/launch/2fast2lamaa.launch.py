import os

from ament_index_python.packages import get_package_prefix, get_package_share_directory
from launch import LaunchDescription
from launch.actions import (
    DeclareLaunchArgument,
    EmitEvent,
    IncludeLaunchDescription,
    LogInfo,
    RegisterEventHandler,
)
from launch.event_handlers import OnProcessExit
from launch.events import Shutdown
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare

IS_MAPPING = os.getenv("IS_MAPPING")
STORAGE_PATH = os.getenv("STORAGE_PATH")
INPUT_IMU_BIAS_FILE = os.path.join("/", "calib", "imu.json")
LIDAR_TYPE = "robosense"
IMU_TYPE = os.getenv("IMU_TYPE", "vectornav")  # or 'xsens'
NAMESPACE = os.getenv("NAMESPACE", "")

if IS_MAPPING is None:
    print("IS_MAPPING is not set")
    exit(1)
elif STORAGE_PATH is None:
    print("STORAGE_PATH is not set")
    exit(1)

IS_MAPPING = IS_MAPPING == "1"

min_range = float(2.0)
max_range = float(200.0)

key_framing = True
key_frame_dist_thr = float(10.0)
key_frame_rot_thr = float(15.0 * 3.14 / 180.0)
key_frame_time_thr = float(0.5)

over_reject = False  # If true, also reject the neighborhood points when performing the dynamic filtering and free space carving.


def generate_launch_description():
    ld = LaunchDescription()

    ld.add_action(
        DeclareLaunchArgument(
            "use_sim_time", default_value="true", description="Use simulation time"
        )
    )
    lamaa_node = Node(
        package="ffastllamaa",
        executable="lidar_scan_odometry",
        name="lidar_scan_odometry",
        namespace=NAMESPACE,
        sigterm_timeout="6000",  # Wait 60 seconds before escalating to SIGTERM
        sigkill_timeout="10",  # Wait 10 more seconds before SIGKILL
        remappings=[
            ("/imu/acc", f"{IMU_TYPE}/data_raw"),
            ("/imu/gyr", f"{IMU_TYPE}/data_raw"),
            ("/lidar_raw_points", f"/{LIDAR_TYPE}/points"),
            ("/undistortion_pose", "estimated_transform"),
        ],
        parameters=[
            {"use_sim_time": LaunchConfiguration("use_sim_time")},
            {
                "low_latency": True
            },  # Set to True for estimation at each scan, False for every second scan
            {"dense_pc_output": False},  # Set to True to output dense point cloud
            {"absolute_time": True},
            {"point_time_multiplier": 1e-6},  # our timestamps our in microseconds
            {"min_range": float(min_range)},
            {"max_range": float(max_range)},
            {"max_feature_range": float(max_range)},
            {"feature_voxel_size": 0.5},
            {"max_feature_dist": 1.5},
            {"loss_function_scale": 0.5},
            {"state_freq": 200.0},
            {"max_associations_per_type": 1000},
            {"planar_only": False},
            {"broken_channels": ""},
            {
                "mode": "imu"
            },  # State representation mode: imu (acc and gyr preint), gyr (gyr preint and const vel), no_imu (const linear and angular vel)
            # Adapting IMU measurements for some weird IMUs
            {"acc_in_m_per_s2": True},
            {"invert_imu": False},
            # Calibration
            {"calib_px": 0.823},
            {"calib_py": -0.106},
            {"calib_pz": -0.375},
            {"calib_rx": -0.003},
            {"calib_ry": 0.003},
            {"calib_rz": 1.568},
            # In case the point cloud is not sorted by time, set this to True
            {"unsorted_pc": False},
        ],
        output="screen",
    )
    gp_map_node = Node(
        package="ffastllamaa",
        executable="gp_map",
        name="gp_map",
        namespace=NAMESPACE,
        output="screen",
        sigterm_timeout="6000",  # Wait 60 seconds before escalating to SIGTERM
        sigkill_timeout="10",  # Wait 10 more seconds before SIGKILL
        remappings=[
            ("/points_input", "lidar_scan_undistorted"),
            ("/pose_input", "estimated_transform"),
        ],
        parameters=[
            {"use_sim_time": LaunchConfiguration("use_sim_time")},
            {"point_cloud_internal_type": True},
            {"voxel_size": 0.30},
            {"neighbourhood_size": 2},
            {"register": True},
            {"register_with_approximate_field": False},
            {"voxel_size_factor_for_registration": 2.0},
            {"max_num_pts_for_registration": 8000},
            {"loss_function_scale": 0.5},
            {
                "use_temporal_weights": False
            },  # If true, registration weight are 10 times bigger for voxels associated to the older scans than for the newer ones
            {"with_init_guess": True},
            {"map_publish_period": 10.0},
            {"key_framing": key_framing},
            {"key_framing_dist_thr": key_frame_dist_thr},
            {"key_framing_rot_thr": key_frame_rot_thr},
            {"key_framing_time_thr": key_frame_time_thr},
            # Free space carving (<= 0.0 to disable it)
            {"min_range": min_range},
            {"free_space_carving_radius": float(50)},
            {"over_reject": over_reject},
            {"last_scan_carving": True},
            # Path to where the map will be saved
            {"map_path": STORAGE_PATH},
            {"submap_length": -1.0 if IS_MAPPING else 200.0},
            {"submap_overlap": 0.2},
            {"write_scans": False},
            {"localization_only": not IS_MAPPING},
        ],
    )

    ld.add_action(lamaa_node)
    ld.add_action(gp_map_node)
    ld.add_action(
        RegisterEventHandler(
            event_handler=OnProcessExit(
                target_action=gp_map_node,
                on_exit=[
                    LogInfo(msg="Mapper exited; tearing down entire system."),
                    EmitEvent(event=Shutdown()),
                ],
            )
        )
    )
    return ld
