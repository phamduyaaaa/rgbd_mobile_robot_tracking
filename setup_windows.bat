@echo off
REM ============================================================================
REM  DA CDT K18 - Tu dong cai moi truong mo phong tren Windows 11
REM  ROS 2 Jazzy + Gazebo Harmonic tren WSL2 (Ubuntu 24.04), hien thi qua WSLg,
REM  render bang GPU qua Mesa D3D12.
REM
REM  Cach dung: dat file nay o thu muc goc do an (canh da_cdt_robot_description\)
REM             roi double-click. May moi can chay 2 lan:
REM               Lan 1: cai WSL2 + Ubuntu 24.04 -> khoi dong lai may, tao user Ubuntu
REM               Lan 2: cai ROS 2, Gazebo, tao workspace va build
REM  Chay lai nhieu lan van an toan: buoc nao da xong se duoc bo qua.
REM
REM  Phan cuoi file (sau dong danh dau #__BASH_SCRIPT_BELOW__) la script bash
REM  duoc tach ra va chay ben trong Ubuntu.
REM ============================================================================
setlocal EnableExtensions
chcp 65001 >nul
title DA CDT K18 - Setup ROS 2 Jazzy + Gazebo Harmonic (WSL2)

set "DISTRO=Ubuntu-24.04"
set "WSL_UTF8=1"
set "PROJECT_DIR=%~dp0"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
REM Duong dan dua cho PowerShell qua bien moi truong ($env:...), khong nhung vao chuoi '...',
REM de duong dan co dau nhay don (vd. C:\Users\O'Brien) khong lam hong lenh.
set "BAT_PATH=%~f0"

if not exist "%PROJECT_DIR%\da_cdt_robot_description\package.xml" (
    echo [LOI] Khong thay da_cdt_robot_description\package.xml canh file nay.
    echo       Hay dat setup_windows.bat o thu muc goc do an.
    goto :fail
)

REM --- 0. Quyen Administrator (can cho wsl --install) -------------------------
REM fltmc chi chay duoc khi co quyen Admin. Khong dung "net session" vi lenh nay cung
REM bao loi khi dich vu Server cua Windows bi tat, gay vong lap tu nang quyen vo han.
REM Tham so --elevated: ban da nang quyen ma van khong co quyen thi dung, khong lap lai.
fltmc >nul 2>&1
if errorlevel 1 (
    if /i "%~1"=="--elevated" (
        echo [LOI] Khong lay duoc quyen Administrator.
        goto :fail
    )
    echo Dang yeu cau quyen Administrator...
    powershell -NoProfile -Command "Start-Process -FilePath $env:BAT_PATH -ArgumentList '--elevated' -Verb RunAs"
    exit /b 0
)

echo.
echo ==== [1/5] Kiem tra WSL2 va %DISTRO% ====
wsl.exe -l -q 2>nul | findstr /i /c:"%DISTRO%" >nul
if not errorlevel 1 goto :distro_found
REM Distro "Ubuntu" (ban mac dinh tren Microsoft Store) neu la 24.04 thi dung luon,
REM khong cai them Ubuntu-24.04 thu hai.
wsl.exe -d Ubuntu -e grep -q "VERSION_CODENAME=noble" /etc/os-release >nul 2>&1
if errorlevel 1 goto :install_wsl
set "DISTRO=Ubuntu"
:distro_found

for /f "usebackq delims=" %%U in (`wsl.exe -d %DISTRO% -e whoami 2^>nul`) do set "WSL_USER=%%U"
if "%WSL_USER%"=="" goto :need_user
if /i "%WSL_USER%"=="root" goto :need_user
echo Da co %DISTRO%, user mac dinh: %WSL_USER%

echo.
echo ==== [2/5] Cap nhat WSL ====
wsl.exe --update

echo.
echo ==== [3/5] Cau hinh RAM cho WSL (%USERPROFILE%\.wslconfig) ====
REM memory = 55%% RAM may (toi thieu 4 GB); khong ghi de neu file da ton tai.
powershell -NoProfile -Command ^
  "$p = Join-Path $env:USERPROFILE '.wslconfig';" ^
  "if (Test-Path $p) { Write-Host ('Giu nguyen file da co: ' + $p); exit 0 }" ^
  "$m = [math]::Max(4, [math]::Floor((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB * 0.55));" ^
  "Set-Content -Path $p -Encoding ascii -Value @('[wsl2]', ('memory=' + $m + 'GB'), 'swap=4GB');" ^
  "Write-Host ('Da tao ' + $p + ' voi memory=' + $m + 'GB, swap=4GB'); exit 10"
if errorlevel 10 (
    echo Can khoi dong lai WSL de ap dung cau hinh RAM moi.
    echo CANH BAO: lenh nay tat MOI distro WSL va Docker Desktop dang chay.
    echo Luu cong viec dang lam trong WSL/Docker, roi nhan phim bat ky de tiep tuc...
    pause >nul
    wsl.exe --shutdown
)

echo.
echo ==== [4/5] Kiem tra GPU ====
set "GPU_ADAPTER="
for /f "usebackq delims=" %%G in (`powershell -NoProfile -Command "if (Get-CimInstance Win32_VideoController | Where-Object Name -match 'NVIDIA') { 'NVIDIA' }"`) do set "GPU_ADAPTER=%%G"
if defined GPU_ADAPTER (
    echo Tim thay GPU NVIDIA: se ep Mesa D3D12 dung card NVIDIA.
) else (
    echo Khong thay GPU NVIDIA: Mesa D3D12 se dung GPU mac dinh cua Windows.
)

echo.
echo ==== [5/5] Cai ROS 2 Jazzy + Gazebo Harmonic trong %DISTRO% ====
echo (Lan dau mat 10-30 phut tuy toc do mang)
set "SH_WIN=%TEMP%\da_cdt_setup_wsl.sh"
powershell -NoProfile -Command ^
  "$c = [IO.File]::ReadAllText($env:BAT_PATH);" ^
  "$m = '#__BASH_SCRIPT_BELOW__';" ^
  "$i = $c.LastIndexOf($m);" ^
  "[IO.File]::WriteAllText($env:SH_WIN, $c.Substring($i + $m.Length).TrimStart().Replace([string][char]13, ''))"
if errorlevel 1 goto :fail

for /f "usebackq delims=" %%P in (`wsl.exe -d %DISTRO% -e wslpath -a "%SH_WIN%"`) do set "SH_WSL=%%P"
for /f "usebackq delims=" %%P in (`wsl.exe -d %DISTRO% -e wslpath -a "%PROJECT_DIR%"`) do set "PROJECT_WSL=%%P"

wsl.exe -d %DISTRO% -u root -e bash "%SH_WSL%" "%WSL_USER%" "%PROJECT_WSL%" "%GPU_ADAPTER%"
if errorlevel 1 goto :fail
del "%SH_WIN%" >nul 2>&1

echo.
echo ============================================================================
echo  HOAN TAT. Mo terminal "Ubuntu 24.04" va chay:
echo      ros2 launch da_cdt_robot_description gazebo.launch.py
echo  Lai robot (terminal Ubuntu thu hai):
echo      ros2 run teleop_twist_keyboard teleop_twist_keyboard
echo  Goi y: cam sac va bat Settings - Power mode - Best performance.
echo ============================================================================
pause
exit /b 0

:install_wsl
echo Chua co %DISTRO%. Dang cai WSL2 va %DISTRO%...
wsl.exe --install -d %DISTRO%
echo.
echo ============================================================================
echo  BUOC TIEP THEO:
echo   1. Khoi dong lai may neu Windows yeu cau.
echo   2. Mo "Ubuntu 24.04" tu Start menu, tao username va password.
echo   3. Chay lai file setup_windows.bat nay.
echo ============================================================================
pause
exit /b 0

:need_user
echo %DISTRO% chua co user thuong (dang la root hoac chua khoi tao).
echo Hay mo "Ubuntu 24.04" tu Start menu, tao username/password, roi chay lai file nay.
pause
exit /b 1

:fail
echo.
echo [LOI] Cai dat that bai. Xem thong bao phia tren.
pause
exit /b 1

#__BASH_SCRIPT_BELOW__
#!/usr/bin/env bash
# Chạy bằng root trong Ubuntu 24.04 (WSL2), được setup_windows.bat gọi.
# Tham số: <user WSL> <đường dẫn thư mục đồ án trong WSL> [<tên GPU cho Mesa D3D12>]
set -euo pipefail

TARGET_USER="$1"
PROJECT_DIR="$2"
GPU_ADAPTER="${3:-}"
PKG_NAME=da_cdt_robot_description
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6 || true)
if [ -z "$USER_HOME" ]; then
  echo "Không tìm thấy user '$TARGET_USER' trong Ubuntu"; exit 1
fi
WS="$USER_HOME/da_cdt_ws"
export DEBIAN_FRONTEND=noninteractive

step() { echo; echo "---- $* ----"; }

step "Kiểm tra hệ thống"
. /etc/os-release
if [ "$VERSION_CODENAME" != "noble" ]; then
  echo "Cần Ubuntu 24.04 (noble), đang là: $VERSION_CODENAME"; exit 1
fi
if [ ! -f "$PROJECT_DIR/$PKG_NAME/package.xml" ]; then
  echo "Không thấy $PROJECT_DIR/$PKG_NAME/package.xml"; exit 1
fi
[ -e /dev/dxg ] && echo "GPU ảo /dev/dxg: có" || echo "CẢNH BÁO: không có /dev/dxg, Gazebo sẽ render bằng CPU (rất chậm)"

step "Locale UTF-8 và công cụ cơ bản"
apt-get update -q
apt-get install -y -q locales curl software-properties-common
locale-gen en_US en_US.UTF-8 >/dev/null
update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

step "Kho apt của ROS 2"
add-apt-repository -y universe >/dev/null
# Kho ROS 2 kiểu cũ (ros2.list + khoá GPG đã hết hạn 06/2025) làm apt-get update báo lỗi.
# Gói ros2-apt-source dưới đây thay thế nó và tự gia hạn khoá.
if [ -f /etc/apt/sources.list.d/ros2.list ]; then
  echo "Xoá kho ROS 2 kiểu cũ: /etc/apt/sources.list.d/ros2.list"
  rm -f /etc/apt/sources.list.d/ros2.list
fi
if dpkg -s ros2-apt-source >/dev/null 2>&1; then
  echo "Đã có kho ROS 2 (ros2-apt-source), bỏ qua"
else
  # GitHub API không đăng nhập giới hạn 60 lần/giờ cho mỗi IP (cả phòng lab dùng chung IP),
  # lỗi thì dùng phiên bản dự phòng. Có thể ghi đè: ROS_APT_SOURCE_VERSION=x.y.z
  ver=$(curl -fsSL https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
        | grep -F '"tag_name"' | awk -F'"' '{print $4}' || true)
  ver=${ver:-${ROS_APT_SOURCE_VERSION:-1.1.0}}
  echo "ros2-apt-source phiên bản $ver"
  curl -fsSL -o /tmp/ros2-apt-source.deb \
    "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ver}/ros2-apt-source_${ver}.${VERSION_CODENAME}_all.deb"
  dpkg -i /tmp/ros2-apt-source.deb
  rm -f /tmp/ros2-apt-source.deb
fi
apt-get update -q

step "Cài ROS 2 Jazzy + Gazebo Harmonic (vài GB)"
apt-get install -y -q \
  ros-jazzy-desktop \
  ros-jazzy-ros-gz \
  ros-jazzy-joint-state-publisher-gui \
  ros-jazzy-teleop-twist-keyboard \
  ros-jazzy-xacro \
  ros-jazzy-depth-image-proc \
  ros-dev-tools \
  mesa-utils

step "Workspace $WS"
mkdir -p "$WS/src"
LINK="$WS/src/$PKG_NAME"
if [ -e "$LINK" ] && [ ! -L "$LINK" ]; then
  echo "CẢNH BÁO: $LINK là thư mục thật, không phải symlink. Giữ nguyên, không ghi đè."
else
  # Symlink tới thư mục đồ án trên ổ Windows: sửa file trong VS Code là WSL thấy ngay.
  ln -sfn "$PROJECT_DIR/$PKG_NAME" "$LINK"
fi

{
  echo "# Môi trường cho đồ án da_cdt (WSL2 + WSLg, không Docker)"
  echo "# Dùng: source ~/da_cdt_ws/setup_env.sh"
  echo "source /opt/ros/jazzy/setup.bash"
  echo "# Render bằng GPU qua D3D12; mặc định WSL dùng llvmpipe (CPU)"
  echo "export GALLIUM_DRIVER=d3d12"
  if [ -n "$GPU_ADAPTER" ]; then
    echo "# Máy có nhiều GPU: chỉ định rõ card rời"
    echo "export MESA_D3D12_DEFAULT_ADAPTER_NAME=$GPU_ADAPTER"
  fi
  echo "if [ -f ~/da_cdt_ws/install/setup.bash ]; then source ~/da_cdt_ws/install/setup.bash; fi"
} > "$WS/setup_env.sh"
chown -R "$TARGET_USER:$TARGET_USER" "$WS"

if ! grep -qF "da_cdt_ws/setup_env.sh" "$USER_HOME/.bashrc"; then
  echo "source ~/da_cdt_ws/setup_env.sh" >> "$USER_HOME/.bashrc"
  echo "Đã thêm 'source ~/da_cdt_ws/setup_env.sh' vào ~/.bashrc"
fi

step "Build (colcon)"
sudo -u "$TARGET_USER" -H bash -c "source /opt/ros/jazzy/setup.bash && cd '$WS' && colcon build --symlink-install"

step "Kiểm tra render GPU"
renderer=$(sudo -u "$TARGET_USER" -H env DISPLAY="${DISPLAY:-:0}" GALLIUM_DRIVER=d3d12 \
           ${GPU_ADAPTER:+MESA_D3D12_DEFAULT_ADAPTER_NAME=$GPU_ADAPTER} \
           glxinfo -B 2>/dev/null | grep "OpenGL renderer" || true)
echo "${renderer:-(không kiểm tra được; mở terminal Ubuntu và chạy: glxinfo -B)}"
case "$renderer" in
  *llvmpipe*) echo "CẢNH BÁO: đang render bằng CPU. Cập nhật driver GPU trên Windows và chạy 'wsl --update'." ;;
esac

echo
echo "Xong phần Ubuntu."
