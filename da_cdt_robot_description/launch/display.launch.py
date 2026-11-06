"""Hiển thị robot trong RViz2, kéo slider joint bằng joint_state_publisher_gui.

ros2 launch da_cdt_robot_description display.launch.py
"""
import os

import xacro
from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description():
    pkg_share = get_package_share_directory('da_cdt_robot_description')
    xacro_file = os.path.join(pkg_share, 'urdf', 'da_cdt_robot.urdf.xacro')
    rviz_config = os.path.join(pkg_share, 'rviz', 'display.rviz')

    robot_description = xacro.process_file(xacro_file).toxml()

    return LaunchDescription([
        Node(
            package='robot_state_publisher',
            executable='robot_state_publisher',
            parameters=[{'robot_description': robot_description}],
            output='screen',
        ),
        Node(
            package='joint_state_publisher_gui',
            executable='joint_state_publisher_gui',
            output='screen',
        ),
        Node(
            package='rviz2',
            executable='rviz2',
            arguments=['-d', rviz_config],
            output='screen',
        ),
    ])
