"""Spawn robot vào Gazebo Harmonic (world rỗng) và hiển thị song song trong RViz2.

ros2 launch da_cdt_robot_description gazebo.launch.py
ros2 launch da_cdt_robot_description gazebo.launch.py rviz:=false
ros2 launch da_cdt_robot_description gazebo.launch.py gui:=false   (nhẹ hơn, chỉ xem bằng RViz2)
ros2 launch da_cdt_robot_description gazebo.launch.py gui_engine:=ogre2   (GUI dùng Ogre 2)
ros2 launch da_cdt_robot_description gazebo.launch.py gui_minimal:=false  (GUI đầy đủ: Entity tree...)
ros2 launch da_cdt_robot_description gazebo.launch.py pointcloud:=true    (tạo /camera/depth/points)

Lái robot (terminal khác):
ros2 run teleop_twist_keyboard teleop_twist_keyboard

Camera (frame_id: link_camera_optical):
/camera/color/image_raw, /camera/color/camera_info   (RGB)
/camera/depth/image_raw, /camera/depth/camera_info   (Depth)
/camera/depth/points                                 (PointCloud2, khi pointcloud:=true)
"""
import os
import shlex

import xacro
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import (AppendEnvironmentVariable, DeclareLaunchArgument,
                            IncludeLaunchDescription, OpaqueFunction)
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def _is_true(value):
    return value.strip().lower() in ('true', '1', 'yes', 'on')


def _gz_sim(context, pkg_share):
    """Dựng tham số dòng lệnh cho gz sim từ các launch argument."""
    gz_args = ['-r', '-v', '3']
    if _is_true(LaunchConfiguration('gui').perform(context)):
        gz_args += ['--render-engine-gui', LaunchConfiguration('gui_engine').perform(context)]
        if _is_true(LaunchConfiguration('gui_minimal').perform(context)):
            gz_args += ['--gui-config',
                        os.path.join(pkg_share, 'config', 'gui_minimal.config')]
    else:
        gz_args.append('-s')
    gz_args.append(LaunchConfiguration('world').perform(context))

    return [IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            os.path.join(get_package_share_directory('ros_gz_sim'),
                         'launch', 'gz_sim.launch.py')),
        launch_arguments={
            'gz_args': ' '.join(shlex.quote(a) for a in gz_args),
            # Đóng cửa sổ Gazebo thì tắt luôn cả launch, tránh sót tiến trình
            'on_exit_shutdown': 'true',
        }.items(),
    )]


def generate_launch_description():
    pkg_share = get_package_share_directory('da_cdt_robot_description')
    xacro_file = os.path.join(pkg_share, 'urdf', 'da_cdt_robot.urdf.xacro')
    rviz_config = os.path.join(pkg_share, 'rviz', 'gazebo.rviz')
    bridge_config = os.path.join(pkg_share, 'config', 'ros_gz_bridge.yaml')

    robot_description = xacro.process_file(xacro_file).toxml()

    return LaunchDescription([
        DeclareLaunchArgument(
            'world',
            default_value=os.path.join(pkg_share, 'worlds', 'da_cdt_world.sdf'),
            description='File world của Gazebo (phải có plugin Sensors cho camera)'),
        DeclareLaunchArgument('gui', default_value='true',
                              description='false: chỉ chạy Gazebo server (không cửa sổ GUI), '
                                          'tiết kiệm RAM/CPU; xem robot qua RViz2'),
        # Ogre 1 nhẹ hơn và chạy mượt hơn Ogre 2 trên WSLg (D3D12); camera phía server
        # vẫn dùng ogre2 theo file world. Dùng gui_engine:=ogre2 để quay lại mặc định của Gazebo.
        DeclareLaunchArgument('gui_engine', default_value='ogre',
                              description='Engine vẽ cửa sổ Gazebo GUI: ogre hoặc ogre2'),
        DeclareLaunchArgument('gui_minimal', default_value='true',
                              description='true: GUI tối giản (config/gui_minimal.config), '
                                          'false: GUI đầy đủ mặc định của Gazebo'),
        DeclareLaunchArgument('rviz', default_value='true',
                              description='Mở RViz2 cùng Gazebo'),
        DeclareLaunchArgument('pointcloud', default_value='false',
                              description='true: tạo /camera/depth/points từ ảnh depth '
                                          '(depth_image_proc), tốn thêm CPU'),

        # Để Gazebo phân giải được package://da_cdt_robot_description/meshes/...
        AppendEnvironmentVariable('GZ_SIM_RESOURCE_PATH',
                                  os.path.dirname(pkg_share)),

        OpaqueFunction(function=_gz_sim, args=[pkg_share]),

        Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            parameters=[{'robot_description': robot_description,
                         'use_sim_time': True}],
            output='screen',
        ),

        # base_footprint nằm ở mặt đất, thả cao 2 cm cho robot rơi nhẹ xuống
        Node(
            package='ros_gz_sim',
            executable='create',
            arguments=['-topic', 'robot_description',
                       '-name', 'da_cdt_robot',
                       '-z', '0.02'],
            output='screen',
        ),

        # Danh sách topic và chiều chuyển xem config/ros_gz_bridge.yaml
        Node(
            package='ros_gz_bridge',
            executable='parameter_bridge',
            parameters=[{'config_file': bridge_config}],
            output='screen',
        ),

        # Point cloud theo frame quang học, tạo từ ảnh depth + ảnh màu + camera_info
        Node(
            package='depth_image_proc',
            executable='point_cloud_xyzrgb_node',
            parameters=[{'use_sim_time': True}],
            remappings=[
                ('rgb/camera_info', '/camera/color/camera_info'),
                ('rgb/image_rect_color', '/camera/color/image_raw'),
                ('depth_registered/image_rect', '/camera/depth/image_raw'),
                ('points', '/camera/depth/points'),
            ],
            condition=IfCondition(LaunchConfiguration('pointcloud')),
            output='screen',
        ),

        Node(
            package='rviz2',
            executable='rviz2',
            arguments=['-d', rviz_config],
            parameters=[{'use_sim_time': True}],
            condition=IfCondition(LaunchConfiguration('rviz')),
            output='screen',
        ),
    ])
