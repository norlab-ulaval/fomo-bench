import os

from ament_index_python.packages import get_package_prefix, get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
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
if IS_MAPPING:
    input_map_name = ""
    output_map_name = f"{STORAGE_PATH}/map.vtk"
else:
    input_map_name = f"{STORAGE_PATH}/map.vtk"
    output_map_name = ""

min_range = float(5.0)
max_range = float(200.0)

key_framing = True
key_frame_dist_thr = float(10.0)
key_frame_rot_thr = float(15.0 * 3.14 / 180.0)
key_frame_time_thr = float(0.5)

over_reject = False  # If true, also reject the neighborhood points when performing the dynamic filtering and free space carving.


def generate_launch_description():
    ld = LaunchDescription()
    share_folder = get_package_share_directory("ros_launchers")
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
    lamaa_node = Node(
        package="ffastllamaa",
        executable="lidar_scan_odometry",
        name="lidar_scan_odometry",
        namespace=NAMESPACE,
        remappings=[
            ("/imu/acc", f"{IMU_TYPE}/data"),
            ("/imu/gyr", f"{IMU_TYPE}/data"),
            ("/lidar_raw_points", f"/{LIDAR_TYPE}/points"),
            ("/undistortion_pose", "estimated_pose"),
        ],
        parameters=[
            {"use_sim_time": LaunchConfiguration("use_sim_time")},
            {
                "low_latency": True
            },  # Set to True for estimation at each scan, False for every second scan
            {"dense_pc_output": False},  # Set to True to output dense point cloud
            {"min_range": float(min_range)},
            {"max_range": float(max_range)},
            {"max_feature_range": float(max_range)},
            {"feature_voxel_size": 0.5},
            {"max_feature_dist": 1.5},
            {"loss_function_scale": 0.5},
            {"state_freq": 200.0},
            {"max_associations_per_type": 1000},
            {"planar_only": False},
            {"broken_channels": "69"},
            {
                "mode": "imu"
            },  # State representation mode: imu (acc and gyr preint), gyr (gyr preint and const vel), no_imu (const linear and angular vel)
            # Adapting IMU measurements for some weird IMUs
            {"acc_in_m_per_s2": True},
            {"invert_imu": False},
            # Calibration
            {"calib_px": 0.0},
            {"calib_py": 0.0},
            {"calib_pz": -0.28},
            {"calib_rx": 2.92077461},
            {"calib_ry": -1.15627809},
            {"calib_rz": -0.00226139},
            # In case the point cloud is not sorted by time, set this to True
            {"unsorted_pc": False},
        ],
        output="screen",
    )
    gp_map_node = (
        Node(
            package="ffastllamaa",
            executable="gp_map",
            name="gp_map",
            namespace=NAMESPACE,
            remappings=[
                ("/points_input", "lidar_scan_undistorted"),
                ("/pose_input", "estimated_pose"),
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
                {"map_publish_period": 0.5},
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
                {"submap_length": 200.0},
                {"submap_overlap": 0.2},
                {"write_scans": False},
            ],
            output="screen",
            on_exit=Shutdown(),
        ),
    )

    ld.add_action(lamaa_node)
    ld.add_action(gp_map_node)
    return ld
