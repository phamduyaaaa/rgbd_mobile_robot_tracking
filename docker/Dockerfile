# Image cho đồ án: osrf/ros:jazzy-desktop-full + các gói desktop-full không có sẵn
# (danh sách khớp với <exec_depend> trong da_cdt_robot_description/package.xml).
# Build một lần (docker compose up --build), các lần sau dùng lại image đã build.
FROM osrf/ros:jazzy-desktop-full

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ros-jazzy-joint-state-publisher-gui \
      ros-jazzy-teleop-twist-keyboard \
      ros-jazzy-xacro \
      ros-jazzy-depth-image-proc \
      mesa-utils \
 && rm -rf /var/lib/apt/lists/*
