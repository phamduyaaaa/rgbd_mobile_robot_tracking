# Lịch sử công nghệ của đồ án

Tài liệu này ghi lại theo thứ tự thời gian các công nghệ đã dùng trong đồ án: ban đầu dùng gì, vì sao chọn, vì sao đổi, và số đo nào dẫn tới quyết định đó. Các con số là số đo thật trên máy phát triển, trừ khi ghi rõ là ước lượng hoặc chưa kiểm chứng.

**Máy phát triển:** laptop Windows 11, CPU AMD Ryzen 7 5800H (8 nhân / 16 luồng), RAM 7,4 GB, GPU rời NVIDIA RTX 3060 Laptop 6 GB + GPU tích hợp AMD Radeon.

## Tóm tắt

```
 SolidWorks ──► URDF (ROS 1, catkin)
                    │  chuyển sang ROS 2
                    ▼
 Docker Desktop + osrf/ros:jazzy-desktop-full ── ROS 2 Jazzy + Gazebo Harmonic
   │  render bằng CPU (llvmpipe)
   ▼
 Docker + GPU qua Mesa D3D12 ──► camera 640×480 → 320×240
   │  thử WSL2 gốc: hiệu năng như Docker
   ▼
 WSL2 gốc + WSLg + D3D12 ──► GUI Gazebo Ogre 2 → Ogre 1 ──► RAM WSL 4 GB + swap
   │
   ▼
 setup_windows.bat (cài tự động)
```

| Giai đoạn | Công nghệ chính | Lý do chuyển sang giai đoạn sau |
|---|---|---|
| 0 | SolidWorks + SW2URDF, package ROS 1 | ROS 1 đã hết hỗ trợ, đồ án cần ROS 2 |
| 1 | Docker Desktop, ROS 2 Jazzy, Gazebo Harmonic | Cần chuyển package sang ROS 2 |
| 2 | ament_cmake, launch Python, ros_gz | Robot chưa lái được |
| 3 | Plugin DiffDrive | Chưa có cảm biến |
| 4 | Camera rgbd_camera (Astra) | Mô phỏng lag |
| 5 | GPU D3D12, giảm độ phân giải, WSL2 gốc, Ogre 1, RAM | Đã đủ mượt, cần đóng gói |
| 6 | Script cài tự động, README | (hiện tại) |

---

## Giai đoạn 0: Điểm xuất phát

### Công nghệ
- **SolidWorks** để thiết kế cơ khí robot: khung, 2 động cơ JGB37-520, 2 bánh xe, bánh caster 2 tầng, camera Orbbec Astra.
- **SW2URDF exporter 1.6** (plugin SolidWorks) để xuất mô hình sang URDF.

### Kết quả nhận được
Plugin tạo ra một package **ROS 1** tên `urdf`:
- Build bằng `catkin` (`CMakeLists.txt`, `package.xml` format 2).
- File launch dạng XML của ROS 1 (`display.launch`, `gazebo.launch`), dùng `gazebo_ros` của **Gazebo Classic**.
- 6 mesh STL (`base_link`, 2 bánh, 2 tầng caster, camera), khối lượng và quán tính tính từ SolidWorks.

### Vấn đề
1. **ROS 1 đã ngừng hỗ trợ** (ROS Noetic hết hạn tháng 5/2025). Toàn bộ hệ sinh thái mới đều ở ROS 2.
2. **Gazebo Classic đã ngừng hỗ trợ** (tháng 1/2025).
3. **Tên package `urdf` trùng với package có sẵn của ROS** (thư viện đọc file URDF). Overlay một package cùng tên sẽ che mất package gốc và có thể làm hỏng các gói phụ thuộc nó.
4. **Tên joint có dấu cách:** `joint _left_wheel`, lỗi do đặt tên trong SolidWorks.

---

## Giai đoạn 1: Chọn nền tảng (ROS 2 Jazzy + Gazebo Harmonic trong Docker)

### Lựa chọn và lý do

| Thành phần | Chọn | Phương án bị loại | Lý do |
|---|---|---|---|
| ROS 2 | **Jazzy Jalisco** (LTS, hỗ trợ đến 5/2029) | Humble (LTS, hết hạn 5/2027) | Thời gian hỗ trợ dài hơn, đi cặp chính thức với Gazebo Harmonic |
| Simulator | **Gazebo Harmonic** (LTS) | Gazebo Classic (đã EOL), Gazebo Fortress (cặp với Humble) | Bản Gazebo chính thức cho Jazzy; hỗ trợ GPU trên WSL2 tốt hơn các bản cũ |
| Môi trường | **Docker Desktop** (backend WSL2) | Cài trực tiếp | Đóng gói môi trường, dễ chia sẻ cho nhóm |
| Image | **`osrf/ros:jazzy-desktop-full`** | `ros:jazzy` (chính thức) | Image chính thức chỉ có bản cơ bản. `desktop-full` có sẵn RViz2, `robot_state_publisher`, `joint_state_publisher_gui`, `ros_gz_sim`, `ros_gz_bridge` và Gazebo Harmonic, nên không cần viết Dockerfile |

### Hiển thị GUI từ container
Windows 11 có sẵn **WSLg**: một máy chủ hiển thị (X11 + Wayland) chạy trong WSL2, cho phép ứng dụng Linux mở cửa sổ ngay trên desktop Windows. Không cần cài VcXsrv hay X410.

Container của Docker Desktop không tự thấy WSLg, nên `docker-compose.yml` phải:
- Mount socket hiển thị: `/run/desktop/mnt/host/wslg/.X11-unix → /tmp/.X11-unix` và `/run/desktop/mnt/host/wslg → /mnt/wslg`. Đây là đường dẫn đặc thù của Docker Desktop.
- Đặt `DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`, `XDG_RUNTIME_DIR`, `PULSE_SERVER`.

### Quyết định tạm thời: `LIBGL_ALWAYS_SOFTWARE=1`
Ban đầu đặt biến này để ép render bằng CPU (Mesa llvmpipe), tránh lỗi OpenGL khi chưa biết container có dùng được GPU hay không. Đây là nguyên nhân chính gây lag ở giai đoạn sau (xem 5.1).

### Tiện ích trong compose
- `network_mode: host` và `ipc: host` để DDS của ROS 2 hoạt động đơn giản.
- Volume riêng cho `build/`, `install/`, `log/` để giữ kết quả `colcon build` sau khi tắt container.
- Lệnh khởi động ghi `source /opt/ros/jazzy/setup.bash` vào `~/.bashrc`, vì `docker compose exec` không đi qua entrypoint của image nên không tự nạp ROS.

---

## Giai đoạn 2: Chuyển package từ ROS 1 sang ROS 2

| Thành phần | ROS 1 (cũ) | ROS 2 (mới) | Ghi chú |
|---|---|---|---|
| Tên package | `urdf` | `da_cdt_robot_description` | Tránh trùng package `urdf` của ROS |
| Build | `catkin` | `ament_cmake` | `package.xml` format 3, cài `launch meshes rviz urdf worlds config` vào `share/` |
| Launch | XML `.launch` | Python `.launch.py` | ROS 2 khuyến nghị launch Python |
| Spawn robot | `gazebo_ros spawn_model` | `ros_gz_sim create -topic robot_description` | API của Gazebo mới |
| Gazebo ↔ ROS | Plugin `gazebo_ros` | `ros_gz_bridge parameter_bridge` | Gazebo mới dùng gz-transport, cần cầu nối sang ROS 2 |
| RViz | `rviz` | `rviz2` + file `.rviz` mới | |

Các sửa đổi trong URDF:
- `package://urdf/...` → `package://da_cdt_robot_description/...` (12 chỗ).
- `joint _left_wheel` → `joint_left_wheel`.
- Thêm plugin `gz-sim-joint-state-publisher-system` để Gazebo phát `/joint_states`.

Để Gazebo tìm được mesh khi URDF dùng `package://`, launch thêm thư mục `share/` của package vào biến `GZ_SIM_RESOURCE_PATH`.

Ghi chú nhỏ: thư mục `urdf/` cũ bị VS Code khoá nên không đổi tên trực tiếp được. Đã sao chép sang thư mục mới, so sánh giống hệt (`diff -r`), rồi mới xoá thư mục cũ.

---

## Giai đoạn 3: Lái robot bằng `/cmd_vel`

### Công nghệ
Plugin **`gz-sim-diff-drive-system`** của Gazebo: nhận `/cmd_vel`, điều khiển vận tốc 2 joint bánh, phát `/odom` và TF `odom → base_link`.

### Thông số đo từ mesh thay vì đoán
Viết script Python đọc file STL nhị phân, tính hộp bao (bounding box) của từng mesh:

| Thông số | Giá trị | Cách tính |
|---|---|---|
| Bán kính bánh xe | 0,034 m | Bán kính hộp bao của `link_left_wheel.STL` |
| Khoảng cách tâm 2 bánh | 0,1842 m | Joint đặt ở y = ±0,082187; tâm bề rộng bánh lệch thêm 0,0099 m mỗi bên |
| Bán kính bánh caster | 0,0125 m | `link_caster2.STL` |
| Độ cao điểm tiếp đất | z ≈ −0,068 m | Bánh chính và bánh caster trùng nhau, đúng như mong đợi |

### Hình va chạm đơn giản hoá
- Bánh xe: hình **trụ** (r = 0,034 m) thay cho mesh STL. Lăn trên mesh tam giác dễ giật và nảy.
- Bánh caster: hình **cầu** (r = 0,0125 m) để trượt mượt theo mọi hướng.
- Ma sát: bánh chủ động `mu = 1,0` để bám, bánh caster `mu = 0,01` để không cản robot.
- Phần hiển thị vẫn giữ mesh gốc từ SolidWorks.

### Kiểm chứng
Gửi `linear.x = 0,2` thì `/odom` tăng theo trục x, nên chiều chạy đúng. Chiều quay chưa được kiểm tra riêng. Gia tốc tối đa (1 m/s², 3 rad/s²) là giá trị tự chọn, cần chỉnh theo động cơ thật.

---

## Giai đoạn 4: Camera RGB và RGB-D (Orbbec Astra)

### Công nghệ
Cảm biến **`rgbd_camera`** của Gazebo. Một cảm biến sinh ra cả ảnh màu, ảnh độ sâu và point cloud, đúng như Astra thật. Thông số theo Astra: góc nhìn ngang 60°, tầm đo đến 8 m.

### World riêng có plugin Sensors
World `empty.sdf` mặc định của Gazebo **không có** plugin `gz-sim-sensors-system`, nên camera không ra hình. Đã tạo `worlds/da_cdt_world.sdf` với các plugin Physics, UserCommands, SceneBroadcaster, Sensors (render engine `ogre2`), cùng một hộp đỏ và một trụ xanh để camera có vật để nhìn.

### Tên topic
Cầu nối đổi tên topic gốc của Gazebo (`/camera/image`, `/camera/depth_image`, `/camera/points`) sang tên theo kiểu driver Astra thật: `/camera/color/image_raw`, `/camera/depth/image_raw`, `/camera/depth/points`, `/camera/color/camera_info`.

### Lỗi hướng point cloud và cách sửa
- **Ban đầu:** gán `frame_id` của cảm biến là `link_camera_optical` (frame quang học chuẩn ROS: z ra trước, x sang phải, y xuống dưới).
- **Đo dữ liệu thật:** giá trị x nhỏ nhất của point cloud là 0,35 (khoảng cách phía trước), z âm là phía mặt đất. Vậy point cloud của Gazebo tính theo hệ **x ra trước, z lên trên**. Nếu để nguyên, trong RViz2 đám điểm sẽ bị xoay 90°.
- **Sửa:** thêm frame `link_camera_lens` (cùng gốc với ống kính, không xoay) và dùng nó làm `gz_frame_id`. Frame `link_camera_optical` vẫn giữ lại cho các node cần chuẩn ROS.
- **Kiểm chứng:** hộp đỏ khai báo ở y = +0,3 xuất hiện trong point cloud ở y ≈ +0,28. Trụ xanh khai báo ở (1,45; −0,4) xuất hiện ở (1,40; −0,37). Khớp.

---

## Giai đoạn 5: Tối ưu hiệu năng

Đây là giai đoạn dài nhất. Mỗi bước dưới đây đều có số đo trước và sau.

### 5.1. Từ render CPU sang GPU (Mesa D3D12)

**Triệu chứng:** lag. Nguyên nhân rõ ràng nhất là `LIBGL_ALWAYS_SOFTWARE=1` từ giai đoạn 1.

**Cách GPU hoạt động trong WSL2:**

```
Ứng dụng → OpenGL → Mesa (driver d3d12) → Direct3D 12 → /dev/dxg (thiết bị ảo)
        → driver GPU của Windows → GPU thật
```

Mesa D3D12 dịch lệnh OpenGL sang Direct3D 12, rồi gửi qua `/dev/dxg` sang driver GPU của Windows.

**Thay đổi trong `docker-compose.yml`:**
- Bỏ `LIBGL_ALWAYS_SOFTWARE=1`.
- Thêm `gpus: all` để container có `/dev/dxg`.
- Mount `/usr/lib/wsl` (chứa `libd3d12.so`, `libd3d12core.so` và driver GPU). Ban đầu tưởng thư viện đã có sẵn ở `/usr/lib/wsl/lib`, thực tế phải mount từ Docker Desktop.
- `GALLIUM_DRIVER=d3d12` để ép Mesa dùng driver D3D12.
- `MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA`, vì máy có 2 GPU (AMD tích hợp + RTX 3060). Không chỉ định thì có thể chọn nhầm card tích hợp.

**Kiểm chứng:** `glxinfo -B` báo `D3D12 (NVIDIA GeForce RTX 3060 Laptop GPU)`, OpenGL 4.6, hardware accelerated.

**Số đo (A/B, cùng world):**

| | Gazebo server | Gazebo GUI |
|---|---|---|
| Render bằng CPU (llvmpipe) | 292% CPU | 188% CPU |
| Render bằng GPU (D3D12) | 146% CPU | 106% CPU |

GPU giảm gần một nửa tải CPU. Trên Windows, mức dùng GPU của container hiện dưới tên tiến trình **`vmwp.exe`** (máy ảo WSL2), không phải tên Gazebo: VRAM tăng từ 14 MiB lên 543 MiB, engine 3D của RTX 3060 khoảng 34%.

### 5.2. Camera chậm: giới hạn ở CPU, không phải GPU

**Triệu chứng:** camera chỉ đạt ~10 Hz thay vì 30 Hz, trong khi GPU chỉ dùng ~8%.

**Khoanh vùng:**
- Đo ngay phía Gazebo (`gz topic -f`, trước cầu nối ROS): ảnh ~10 Hz, còn `/clock` 1000 Hz. Vậy cầu nối không phải nguyên nhân.
- Real-time factor = 1,0, nên vật lý không chậm.
- Kết luận: cảm biến RGB-D xử lý từng điểm ảnh trên CPU (point cloud 307.200 điểm mỗi khung ở 640×480).

**Thử nghiệm:** hạ xuống 320×240 (giảm 4 lần số điểm ảnh) thì ảnh tăng lên ~22 Hz (khi không mở RViz2).

**Quyết định:** chọn 320×240. Trong cấu hình đầy đủ (Gazebo GUI + RViz2), ảnh màu đạt ~15 Hz, ảnh độ sâu ~14 Hz, point cloud ~10 Hz.

### 5.3. RViz2 và point cloud
`rviz2` chiếm ~100% một nhân CPU. Tắt lớp "Depth PointCloud" trong RViz2 chỉ giảm xuống ~83%, nên đây không phải thủ phạm chính. Vẫn tắt mặc định vì không mất gì: topic vẫn được phát, tick lại khi cần xem. Ảnh RGB và ảnh độ sâu vẫn hiển thị.

### 5.4. Đánh giá đề xuất "Docker Engine trong WSL thay cho Docker Desktop"
Một tài liệu tham khảo đề xuất bỏ Docker Desktop, cài docker-ce trong Ubuntu WSL. Đánh giá trước khi làm:
- Ubuntu-24.04 và `docker-desktop` **chạy chung một máy ảo WSL2** (cùng kernel, cùng RAM). WSLg, `/dev/dxg` và Mesa D3D12 là cùng một cơ chế dù dùng Docker loại nào. Docker không nằm trên đường hiển thị.
- Lợi ích thật của đề xuất là mạng (node ROS ngoài container nói chuyện với trong container) và tốc độ đọc file trên ext4. Cả hai đều không liên quan đến lag.
- Đề xuất có `memory=12GB` trong `.wslconfig`, **gây hại** trên máy chỉ có 7,4 GB RAM.

Kết luận: không làm theo, và chuyển sang đo trực tiếp WSL gốc để có bằng chứng.

### 5.5. WSL2 gốc (không Docker): hiệu năng như nhau

Cài `ros-jazzy-ros-gz` vào Ubuntu-24.04 (đã có sẵn ROS Jazzy desktop). Tạo workspace riêng `~/da_cdt_ws`, không đụng tới `~/ros2_ws` có sẵn. `src/` là symlink tới thư mục đồ án trên ổ C:, nên chỉ có một bản mã nguồn.

**Phát hiện:** WSL gốc mặc định render bằng **CPU (llvmpipe)**. Phải đặt `GALLIUM_DRIVER=d3d12` mới dùng được GPU. Biến này được đưa vào `~/da_cdt_ws/setup_env.sh`.

| Chỉ số (GUI + RViz2, 320×240) | Docker Desktop | WSL2 gốc |
|---|---|---|
| Ảnh RGB | ~15 Hz | ~13,7 Hz |
| Ảnh độ sâu | ~13,8 Hz | ~14,8 Hz |
| Gazebo server | ~148% | ~145% |
| Gazebo GUI | ~104% | ~104% |
| RViz2 | ~108% | ~108% |

Chênh lệch nằm trong sai số. **Docker không phải nguyên nhân gây lag.** Từ đây chọn WSL gốc vì tiện hơn (không cần khởi động container). Docker vẫn giữ làm phương án thay thế.

### 5.6. Sự cố: Gazebo server "mồ côi"
Khi chạy trên WSL, log có cảnh báo:

```
[Wrn] Found additional publishers on /stats, using namespaced stats topic only
[Wrn] Found additional publishers on /clock, using namespaced clock topic only
```

Nguyên nhân: một Gazebo server sót lại từ lần đo hiệu năng trước, chạy ngầm 8 phút, ngốn **137% CPU và 630 MB RAM**, và phát chồng topic camera với mô phỏng thật. Lệnh spawn robot thậm chí có thể đã đưa robot vào nhầm bản thừa này.

Bài học:
- Thấy cảnh báo này nghĩa là đang có 2 Gazebo. Chạy `pkill -f "gz sim"` rồi chạy lại.
- Khi tự động hoá đo đạc: chạy launch trong process group riêng (`setsid`), kill cả nhóm, rồi kiểm tra lại không còn tiến trình sót.
- `pkill -f <mẫu>` trong `bash -c "...<mẫu>..."` sẽ kill luôn chính shell đó, vì dòng lệnh của shell cũng khớp mẫu.

### 5.7. Bước đột phá: GUI Gazebo dùng Ogre 1 thay cho Ogre 2

**Quan sát then chốt:** RViz2 mượt nhưng Gazebo lag, dù cả hai cùng hiển thị qua WSLg và cùng dùng GPU D3D12.

**Đo riêng tiến trình GUI của Gazebo:**

| Trường hợp | GUI (CPU) |
|---|---|
| World hiện tại | 106% |
| World rỗng, không robot, không camera | 112% |
| Tắt bóng đổ | 104% |

Robot, camera và bóng đổ đều không phải nguyên nhân. GUI vẫn ngốn hơn một nhân CPU ngay cả với world rỗng.

**Ogre là gì:** Ogre (Object-Oriented Graphics Rendering Engine) là engine đồ hoạ 3D mã nguồn mở mà cả Gazebo lẫn RViz2 dùng để vẽ. Có hai thế hệ:
- **Ogre 1:** thiết kế cũ, đơn giản, ít lệnh vẽ. **RViz2 dùng Ogre 1.**
- **Ogre 2 (Ogre-Next):** viết lại cho GPU hiện đại, vật liệu theo vật lý (PBS), bóng đổ đẹp, nhiều lượt vẽ mỗi khung. **Gazebo Harmonic dùng Ogre 2 mặc định.**

**Giả thuyết** (phù hợp với số đo, nhưng chưa xác định được chính xác tính năng nào chậm): trên WSL2, mỗi lệnh OpenGL phải được Mesa dịch sang D3D12 rồi chuyển qua máy ảo. Ogre 2 gửi nhiều lệnh hơn, dùng các tính năng OpenGL hiện đại có thể đi vào nhánh chậm của lớp dịch. Ogre 1 gửi ít lệnh hơn nên chịu chi phí dịch thấp hơn.

**Thay đổi:** thêm tham số `gui_engine` (mặc định `ogre`) vào launch, truyền cờ `--render-engine-gui ogre` cho Gazebo. Camera phía server vẫn dùng `ogre2` theo file world, nên dữ liệu camera không đổi.

**Kết quả:** GUI Gazebo giảm từ ~104% xuống **~65–69% CPU**, và người dùng xác nhận mượt hơn rõ rệt. Đây là thay đổi có tác động lớn nhất.

**Đánh đổi:** hình trong cửa sổ Gazebo trông đơn giản hơn. Một số cảm biến sau này (như `gpu_lidar`, camera phân đoạn ảnh) chỉ chạy trên Ogre 2, nhưng chúng chạy phía server nên không bị ảnh hưởng.

### 5.8. RAM cho WSL và GUI tối giản

**RAM:**
- Máy có 7,4 GB. WSL2 mặc định chỉ lấy một nửa (3,5 GB, swap 1 GB). Windows còn trống ~0,8 GB khi mô phỏng chạy.
- Đã tạo `%USERPROFILE%\.wslconfig` với `memory=4GB`, `swap=4GB`. Sau `wsl --shutdown`, WSL có 3,9 GB (phần chênh do kernel giữ lại) và swap 4 GB. Docker Desktop chạy trong cùng máy ảo WSL2 nên cũng nhận cấu hình này (thấy 4,1 GB).
- Không đặt cao hơn vì Windows cũng cần RAM.

**Đính chính:** ban đầu tôi cho rằng WSL bị thiếu RAM vì `free -m` có lúc báo cột `free` chỉ còn **70 MB**. Đó là cách đọc sai: Linux dùng RAM nhàn rỗi làm bộ nhớ đệm (cột `buff/cache`), nên phải xem cột **`available`**, và lúc đó vẫn còn **~1,9 GB**. Sau khi tăng RAM, một lượt mô phỏng đầy đủ (Gazebo GUI + RViz2) dùng ~1,8 GB và **0 MB swap**. Vậy **bên trong máy ảo** RAM không thiếu. Điều này không loại trừ áp lực RAM **phía Windows**: Windows chỉ còn trống 0,3–0,8 GB và phải nén RAM (Memory Compression ~1 GB).

**Bước ngoặt theo cảm nhận người dùng:** ngay cả với Ogre 1, người dùng vẫn phải thu nhỏ cửa sổ mới đủ mượt. Bước tạo khác biệt rõ là bước này, nhưng nó thay đổi **4 yếu tố cùng lúc**:
1. `.wslconfig`: RAM 4 GB + swap 4 GB.
2. `wsl --shutdown`: khởi động lại toàn bộ máy ảo WSL2 và WSLg, tắt Docker Desktop.
3. Cắm sạc + Power mode → Best performance (trước đó GPU đo được chỉ chạy 210 MHz / 10 W).
4. GUI tối giản (đã đo riêng: ảnh hưởng rất nhỏ).

Chưa tách được yếu tố nào là chính. Xem phần kiểm chứng A/B bên dưới.

**GUI tối giản** (`config/gui_minimal.config`): giữ khung 3D, điều khiển góc nhìn, Play/Pause, bảng thời gian thực. Bỏ Entity tree, Component inspector và các công cụ chỉnh world.

| | GUI đầy đủ (17–18 plugin) | GUI tối giản (6 plugin) |
|---|---|---|
| CPU cửa sổ Gazebo | 69% | 65% |
| RAM cửa sổ Gazebo | 483 MB | 421 MB |

Mức lợi rất nhỏ (CPU nằm trong sai số đo). Vẫn để mặc định, có thể tắt bằng `gui_minimal:=false`.

**Lỗi phụ phát hiện khi đo:** nếu Gazebo vừa bị tắt cưỡng bức rồi chạy lại ngay, cửa sổ có thể báo `Failed to create OpenGL context`. Lỗi tự hết sau vài giây.

### 5.9. Các yếu tố phía Windows
- **Chế độ nguồn:** lúc mô phỏng, RTX 3060 chỉ chạy ở xung 210 MHz và 10 W, tức đang ở mức tiết kiệm điện. Nên cắm sạc và bật Power mode → Best performance.
- Đóng ứng dụng nặng (trình duyệt, Docker Desktop khi dùng WSL gốc) để Windows còn RAM.

### 5.10. Thử lại Docker sau các tối ưu

Vì Docker và WSL gốc có hiệu năng như nhau (5.5), Docker lại hấp dẫn vì tiện hơn: môi trường đóng gói sẵn, dễ chuyển máy. Đo lại trong Docker sau khi đã có Ogre 1 và RAM mới (launch và `.wslconfig` dùng chung với WSL gốc):

| Chỉ số | A. Gazebo GUI + RViz2 | B. Chỉ Gazebo GUI |
|---|---|---|
| Ảnh RGB | 16,8 Hz | 27,8 Hz |
| Ảnh độ sâu | 17,2 Hz | 29,0 Hz |
| Gazebo server | 210% CPU | 201% CPU |
| Gazebo GUI | 60% CPU | 74% CPU |
| RViz2 | 62% CPU | (tắt) |
| Real-time factor | 1,00 | 0,73 (một lần đọc duy nhất, cần đo lại) |
| RAM máy ảo dùng / swap | 1,8 GB / 0 MB | 1,6 GB / 0 MB |

- GUI Gazebo trong Docker (60–74%) cùng mức với WSL gốc sau khi đổi Ogre 1 (65–69%).
- Khi không mở RViz2, camera gần đạt 30 Hz như cấu hình. RViz2 tranh CPU với cảm biến nên khi mở cả hai, camera còn ~17 Hz.

**Docker "mang đi là chạy":**
- **Thay `gpus: all` bằng `devices: [/dev/dxg]`.** Thử nghiệm cho thấy chỉ cần thiết bị GPU ảo `/dev/dxg` là Mesa D3D12 đã render bằng RTX 3060. `gpus: all` chỉ phục vụ CUDA/`nvidia-smi` (đồ án không dùng), và làm compose báo lỗi trên máy không có NVIDIA. `/dev/dxg` là cơ chế chung của WSL2 cho GPU NVIDIA, AMD, Intel. Bỏ luôn `NVIDIA_VISIBLE_DEVICES`, `NVIDIA_DRIVER_CAPABILITIES`.
- **Giữ `MESA_D3D12_DEFAULT_ADAPTER_NAME=NVIDIA`:** thử đặt tên card không tồn tại thì Mesa vẫn tự chọn card khác, không lỗi. Vậy biến này an toàn trên mọi máy.
- **Tự build khi container khởi động:** trên máy mới, volume `install/` trống. Container chạy `colcon build --symlink-install` mỗi lần khởi động (vài giây) và in `[da_cdt] Build OK` vào log.
- **Kiểm chứng như máy mới:** chạy một project Docker riêng với volume trống. Container tự build xong sau ~6 giây, có `/dev/dxg`, terminal mở bằng `docker compose exec` tìm thấy package và launch đọc được đủ tham số.
- `.wslconfig` không nằm trong thư mục đồ án, nên README hướng dẫn tạo trên máy mới.

**Sửa thêm trong `docker-compose.yml`: `init: true`.** Tiến trình gốc của container là `sleep infinity`, không thu dọn tiến trình con mồ côi. Mỗi lần tắt launch để lại các tiến trình zombie (`rviz2 <defunct>`, `robot_state_pub <defunct>`). Zombie không tốn CPU/RAM nhưng tích tụ dần. `init: true` cho Docker dùng `docker-init` (tini) làm tiến trình gốc để thu dọn chúng.

---

## Giai đoạn 6: Đóng gói

- **`setup_windows.bat`:** một file duy nhất cài toàn bộ môi trường trên Windows 11 mới. Phần batch lo phía Windows: quyền Administrator, `wsl --install`, `.wslconfig` (55% RAM, tối thiểu 4 GB), phát hiện GPU NVIDIA. Phần bash nhúng ở cuối file được tách ra và chạy trong Ubuntu: kho apt ROS 2, cài gói, tạo workspace, `setup_env.sh`, build, kiểm tra render GPU. Chạy lại nhiều lần vẫn an toàn.
- **`README.md`:** giới thiệu và cách chạy.
- **Tài liệu này.**

---

## Giai đoạn 7: Rà soát mã nguồn và sửa lỗi

Rà soát toàn bộ mã nguồn (đọc code, không chạy), rồi sửa. **Các thay đổi dưới đây chưa được chạy kiểm chứng** trên máy thật; cần chạy lại mô phỏng và đo như các giai đoạn trước.

**Mô hình robot**
- **Tách URDF thành xacro:** `da_cdt_robot_core.xacro` (số liệu từ SolidWorks) và `da_cdt_robot.gazebo.xacro` (plugin, cảm biến, ma sát). Lý do: xuất lại từ SolidWorks sẽ ghi đè toàn bộ file URDF, làm mất các phần sửa tay.
- **Va chạm thân robot:** thay `base_link.STL` (~152 nghìn tam giác) bằng hình trụ r = 0,1 m, và mesh camera (~16 nghìn tam giác) bằng hình hộp. Kích thước lấy từ hộp bao của mesh. Đáy thân cách mặt đất ~2 cm.
- **Caster `fixed`:** ma sát joint 0,1 N·m lớn gấp ~400 lần momen do tiếp đất tạo ra (~3·10⁻⁴ N·m), nên caster chưa bao giờ xoay. Đổi 2 joint thành `fixed` và giữ link riêng (`preserveFixedJoint`) để ma sát thấp chỉ áp cho hình cầu.
- **`base_footprint`:** thêm làm gốc cây TF, nằm ở mặt đất. DiffDrive phát `odom → base_footprint`. Hết cảnh báo KDL về quán tính ở root link.
- **DiffDrive:** thêm giới hạn vận tốc (0,5 m/s, 4 rad/s, giá trị tạm) và giới hạn giảm tốc. Tính từ khối lượng trong URDF: trọng tâm nằm trước trục bánh ~1,7 cm, cao ~10 cm, nên tăng tốc tiến quá ~1,6 m/s² robot sẽ chổng đầu (caster ở phía trước).
- **Camera:** `gz_frame_id` đổi sang `link_camera_optical`, nên ảnh và `camera_info` đúng chuẩn ROS. Point cloud của Gazebo (hệ x ra trước) không còn được bridge; thay vào đó `depth_image_proc` tạo lại point cloud từ ảnh depth khi chạy với `pointcloud:=true`. Bỏ frame `link_camera_lens`.

**Launch và cầu nối**
- Cầu nối chuyển sang `config/ros_gz_bridge.yaml`, các topic camera đặt `lazy: true`: không node nào xem thì không chuyển, và Gazebo cũng không phải tính.
- `gz_args` dựng bằng Python thường (`OpaqueFunction`) thay cho chuỗi `PythonExpression`. `gui:=True`/`1` giờ cũng được hiểu là bật.
- `on_exit_shutdown`: đóng cửa sổ Gazebo thì tắt cả launch, tránh sót tiến trình (xem 5.6).

**Cài đặt**
- `setup_windows.bat`: kiểm tra quyền bằng `fltmc` thay cho `net session` (lệnh này lỗi khi dịch vụ Server tắt, gây vòng lặp tự nâng quyền); xoá kho ROS 2 kiểu cũ có khoá GPG hết hạn; phiên bản dự phòng khi GitHub API bị giới hạn; dùng distro `Ubuntu` có sẵn nếu là 24.04; cảnh báo trước `wsl --shutdown`; cài thêm `xacro`, `depth_image_proc`.
- `docker-compose.yml`: `healthcheck` để `docker compose up -d --wait` chờ build xong.
- Xoá `.vscode/settings.json` (đường dẫn tuyệt đối, và CMake Tools không configure được package `ament_cmake` trên Windows).

---

## Vì sao hiện tại mượt

1. **Bước ngoặt theo cảm nhận người dùng: bước 5.8**, gồm RAM WSL 4 GB + swap, khởi động lại WSL, cắm sạc + Best performance. Bốn yếu tố đổi cùng lúc nên chưa xác định được yếu tố nào là chính (đang kiểm chứng A/B).
2. **GUI Gazebo dùng Ogre 1:** CPU cửa sổ Gazebo từ ~104% xuống ~65–69%. Mượt hơn rõ, nhưng một mình nó vẫn phải thu nhỏ cửa sổ.
3. **Loại bỏ Gazebo server mồ côi:** giải phóng ~137% CPU và 630 MB RAM bị chiếm vô ích.
4. **GPU qua D3D12:** giảm gần một nửa tải so với render bằng CPU.
5. **Camera 320×240:** giảm tải xử lý RGB-D phía server.
6. **Phụ:** tắt lớp point cloud trong RViz2, GUI tối giản.

**Không phải nguyên nhân:** Docker hay WSL gốc, vì hiệu năng như nhau (5.5 và 5.10).

**Lưu ý về phương pháp:** số đo CPU của tiến trình không phản ánh trực tiếp số khung hình người dùng thấy, và nhiều thay đổi được làm cùng lúc. Cảm nhận của người dùng là thước đo cuối cùng cho độ mượt.

## Hiện trạng công nghệ

| Lớp | Công nghệ |
|---|---|
| Hệ điều hành | Windows 11 + WSL2 (Ubuntu 24.04) |
| Hiển thị | WSLg (X11/Wayland tích hợp sẵn trong Windows 11) |
| GPU | Mesa D3D12 qua `/dev/dxg` (`GALLIUM_DRIVER=d3d12`) |
| Middleware | ROS 2 Jazzy |
| Mô phỏng | Gazebo Harmonic (gz-sim 8): server render camera bằng Ogre 2, cửa sổ GUI bằng Ogre 1 |
| Cầu nối | `ros_gz_bridge`, `ros_gz_sim` |
| Hiển thị dữ liệu | RViz2 (Ogre 1) |
| Điều khiển | Plugin DiffDrive, `teleop_twist_keyboard` |
| Cảm biến | `rgbd_camera` 320×240, FOV 60°, 0,1–8 m |
| Build | `colcon`, `ament_cmake`, `--symlink-install` |
| Phương án thay thế | Docker Desktop + `osrf/ros:jazzy-desktop-full` (hiệu năng tương đương) |

## Vấn đề còn tồn tại

- Các thay đổi ở giai đoạn 7 chưa được chạy kiểm chứng. Cần kiểm tra: point cloud từ `depth_image_proc` khớp vị trí hộp đỏ/trụ xanh như mục 4; caster vẫn trượt mượt (`gz sdf -p` thấy `mu` = 0,01 trên hình cầu); camera có nhanh hơn nhờ `lazy` không.
- Cảnh báo không ảnh hưởng: `gz_frame_id` không có trong chuẩn SDF (vẫn hoạt động).
- Chiều quay chưa được kiểm tra bằng chạy thử (phân tích thì đúng: `joint_left_wheel` ở y > 0). Thử gửi `angular.z > 0` và xem yaw trong `/odom` có tăng không.
- Giới hạn vận tốc/gia tốc của DiffDrive là giá trị tạm, cần chỉnh theo động cơ JGB37-520 thật. Khối lượng trong CAD có thể chưa tính cell pin 21700 (CSV chỉ liệt kê đế pin).
- Camera vẫn chỉ đạt ~15 Hz (không phải 30 Hz) do xử lý RGB-D trên CPU.

## Hướng phát triển

- **Ubuntu chạy thật (dual-boot)** với driver NVIDIA: bỏ hẳn lớp dịch OpenGL → D3D12 và máy ảo. Khi đó có thể dùng lại `gui_engine:=ogre2` để có hình đẹp mà vẫn mượt. Chưa kiểm chứng trên máy này.
- Đặt camera 15 Hz, bước vật lý 2 ms để giảm tải Gazebo server.
- Dùng `depthimage_to_laserscan` để tạo dữ liệu laser từ Astra, rồi chạy `slam_toolbox` và Nav2 (đã có `base_footprint`).
- Chuyển sang `gz_ros2_control` + `diff_drive_controller`, và micro-ROS trên ESP32 cho robot thật, để mô phỏng và robot thật dùng chung bộ điều khiển và topic.
