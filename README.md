# Đồ án CĐT K18: Mô phỏng robot di động vi sai

Robot di động 2 bánh vi sai + bánh caster, gắn camera RGB-D **Orbbec Astra**. Mô hình cơ khí thiết kế trên SolidWorks, xuất sang URDF và mô phỏng bằng **ROS 2 Jazzy + Gazebo Harmonic** chạy trên Windows 11 qua **WSL2**.

Robot làm được trong mô phỏng:
- Lái bằng topic `/cmd_vel` (plugin DiffDrive của Gazebo), phát odometry `/odom` và TF.
- Phát ảnh màu, ảnh độ sâu và point cloud từ camera Astra.
- Hiển thị mô hình, TF, ảnh camera trong RViz2.

Lịch sử các lựa chọn công nghệ và lý do thay đổi: xem [docs/LICH_SU_CONG_NGHE.md](docs/LICH_SU_CONG_NGHE.md).

## Cấu trúc thư mục

```
da_cdt_k18/
├── setup_windows.bat              # Cài tự động toàn bộ môi trường trên Windows 11
├── docker-compose.yml             # Phương án thay thế: chạy trong Docker
├── docker/Dockerfile              # Image Docker: desktop-full + các gói còn thiếu
├── docs/LICH_SU_CONG_NGHE.md      # Lịch sử công nghệ
└── da_cdt_robot_description/      # Package ROS 2 (ament_cmake)
    ├── urdf/
    │   ├── da_cdt_robot.urdf.xacro    # File chính, launch đọc file này
    │   ├── da_cdt_robot_core.xacro    # Link/joint/quán tính/mesh (số liệu từ SolidWorks)
    │   ├── da_cdt_robot.gazebo.xacro  # Plugin Gazebo (DiffDrive, camera), ma sát
    │   └── da_cdt_robot.csv           # Cấu hình SolidWorks to URDF Exporter (bản xuất gốc)
    ├── meshes/*.STL               # Mesh xuất từ SolidWorks
    ├── worlds/da_cdt_world.sdf    # World Gazebo (có plugin Sensors cho camera)
    ├── launch/gazebo.launch.py    # Mô phỏng Gazebo + RViz2
    ├── launch/display.launch.py   # Chỉ xem mô hình trong RViz2
    ├── rviz/                      # Cấu hình RViz2
    └── config/
        ├── gui_minimal.config     # Cấu hình Gazebo GUI tối giản
        └── ros_gz_bridge.yaml     # Danh sách topic cầu nối Gazebo <-> ROS 2
```

**Xuất lại mô hình từ SolidWorks:** không chép đè file URDF mới vào package. Chỉ cập nhật khối lượng, quán tính, vị trí/trục joint và mesh trong `da_cdt_robot_core.xacro`. Hình va chạm đơn giản hoá, `base_footprint`, caster `fixed` và toàn bộ phần Gazebo là sửa tay, phải giữ lại.

## Yêu cầu

- Windows 11, đã bật ảo hoá (Virtualization) trong BIOS.
- GPU có driver mới (khuyến nghị NVIDIA). Không có GPU thì Gazebo render bằng CPU, rất chậm.
- RAM khuyến nghị 8 GB (đã chạy được trên máy 7,4 GB). Dung lượng trống khoảng 10 GB.

## Cài đặt

Double-click **`setup_windows.bat`** ở thư mục gốc (sẽ hỏi quyền Administrator).

- **Máy chưa có WSL:** lần chạy đầu chỉ cài WSL2 + Ubuntu 24.04. Khởi động lại máy, mở "Ubuntu 24.04" từ Start menu để tạo username/password, rồi **chạy lại file bat**.
- **Lần chạy thứ hai** (hoặc máy đã có Ubuntu 24.04): cài ROS 2 Jazzy, Gazebo Harmonic, tạo workspace `~/da_cdt_ws` và build.

Script chạy lại nhiều lần vẫn an toàn. Workspace dùng symlink tới thư mục đồ án trên Windows, nên sửa code trong VS Code là WSL thấy ngay.

## Chạy mô phỏng

Mở terminal **Ubuntu 24.04** (môi trường đã được tự nạp qua `~/.bashrc`):

```bash
# Gazebo + RViz2
ros2 launch da_cdt_robot_description gazebo.launch.py
```
```bash
# Chỉ xem mô hình URDF trong RViz2 (kéo thanh trượt để xoay joint)
ros2 launch da_cdt_robot_description display.launch.py
```

Lái robot ở terminal Ubuntu thứ hai (`i` tiến, `,` lùi, `j`/`l` quay, `k` dừng):

```bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard
```

### Tuỳ chọn của `gazebo.launch.py`

| Tham số | Mặc định | Ý nghĩa |
|---|---|---|
| `gui` | `true` | `false`: không mở cửa sổ Gazebo, chỉ xem bằng RViz2 |
| `gui_engine` | `ogre` | Engine vẽ cửa sổ Gazebo. `ogre` mượt hơn trên WSL; `ogre2` đẹp hơn |
| `gui_minimal` | `true` | `false`: GUI đầy đủ (thêm hình khối, kéo thả vật thể, cây thực thể) |
| `rviz` | `true` | `false`: không mở RViz2 |
| `pointcloud` | `false` | `true`: tạo `/camera/depth/points` từ ảnh depth (tốn thêm CPU). Bật thêm lớp *Depth PointCloud* trong RViz2 để xem |
| `world` | `worlds/da_cdt_world.sdf` | File world khác (phải có plugin Sensors) |

Ví dụ: `ros2 launch da_cdt_robot_description gazebo.launch.py gui:=false`

### Topic chính

| Topic | Kiểu | Nội dung |
|---|---|---|
| `/cmd_vel` | `geometry_msgs/Twist` | Lệnh vận tốc cho robot |
| `/odom` | `nav_msgs/Odometry` | Odometry từ DiffDrive |
| `/joint_states`, `/tf` | | Trạng thái joint, cây toạ độ (`odom → base_footprint → base_link → ...`) |
| `/camera/color/image_raw` | `sensor_msgs/Image` | Ảnh màu 320×240 |
| `/camera/depth/image_raw` | `sensor_msgs/Image` | Ảnh độ sâu (32FC1, mét) |
| `/camera/color/camera_info`, `/camera/depth/camera_info` | `sensor_msgs/CameraInfo` | Thông số camera |
| `/camera/depth/points` | `sensor_msgs/PointCloud2` | Point cloud (chỉ khi `pointcloud:=true`) |

Mọi dữ liệu camera mang `frame_id` = `link_camera_optical` (frame quang học chuẩn ROS: z ra trước).

Topic camera chỉ được chuyển khi có node đăng ký (`lazy` trong `config/ros_gz_bridge.yaml`), nên tắt lớp ảnh trong RViz2 cũng giảm tải cho Gazebo.

## Sửa code

- Sửa file có sẵn (URDF, launch, world, rviz): tắt launch (Ctrl+C) rồi chạy lại.
- Thêm file hoặc thư mục mới: build lại.
  ```bash
  cd ~/da_cdt_ws && colcon build --symlink-install && source ~/da_cdt_ws/setup_env.sh
  ```

## Phương án thay thế: Docker

Hiệu năng tương đương WSL gốc (đã đo). Chạy được với GPU NVIDIA, AMD hoặc Intel. Mang sang máy khác chỉ cần chép cả thư mục `da_cdt_k18`.

**Cài đặt trên máy mới (một lần):**

1. Cài [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows 11, dùng backend WSL2 mặc định), cập nhật driver GPU.
2. Cấp RAM cho WSL2 (bỏ qua nếu đã chạy `setup_windows.bat` hoặc đã có `.wslconfig`). Chạy trong PowerShell; lệnh tự đặt `memory` = 55% RAM máy (tối thiểu 4 GB) như `setup_windows.bat`, và không ghi đè file đã có:
   ```powershell
   $p = "$env:USERPROFILE\.wslconfig"
   if (Test-Path $p) { "Da co $p, giu nguyen" } else {
     $m = [math]::Max(4, [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB * 0.55))
     Set-Content $p "[wsl2]`nmemory=${m}GB`nswap=4GB"
     wsl --shutdown   # tắt mọi distro WSL và Docker Desktop đang chạy
   }
   ```
   Sau đó mở lại Docker Desktop.
3. Cắm sạc, bật Settings → Power mode → Best performance.

**Chạy** (trong thư mục `da_cdt_k18`):

```bash
docker compose up -d --build --wait # lần đầu tải và build image vài GB; chờ đến khi package build xong
docker compose exec ros2 bash        # mở terminal trong container
ros2 launch da_cdt_robot_description gazebo.launch.py
```

Lái robot: mở thêm terminal bằng `docker compose exec ros2 bash` rồi chạy `ros2 run teleop_twist_keyboard teleop_twist_keyboard`.

- Thêm file hoặc thư mục mới vào package: chạy `docker compose restart` (container tự build lại khi khởi động), hoặc `colcon build --symlink-install` trong container.
- Không chạy mô phỏng trong Docker và WSL gốc cùng lúc: hai Gazebo sẽ phát chồng topic.

## Sự cố thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| Rất chậm | Chạy `glxinfo -B \| grep renderer`. Phải ra `D3D12 (...)`; nếu ra `llvmpipe` thì chạy `source ~/da_cdt_ws/setup_env.sh` |
| Log có `Found additional publishers on /stats` | Có Gazebo khác đang chạy ngầm: `pkill -f "gz sim"` rồi chạy lại |
| Cửa sổ Gazebo báo `Failed to create OpenGL context` ngay sau khi Gazebo bị tắt đột ngột | Đợi vài giây rồi chạy lại |
| Cửa sổ không hiện | `echo $DISPLAY` phải ra `:0`; nếu không, chạy `wsl --shutdown` trong PowerShell rồi mở lại Ubuntu |
| Vẫn giật | Cắm sạc, bật Power mode → Best performance, đóng bớt ứng dụng nặng (trình duyệt, Docker Desktop) |
