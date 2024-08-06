#! /bin/bash

clean_progress() {
  local scale=$1
  local postfix=$2
  local last_value=$scale
  while IFS= read -r line; do
    value=$((${line} * ${scale} / 100))
    if [ "$last_value" != "$value" ]; then
      echo ${value}${postfix}
      last_value=$value
    fi
  done
}

if [ $EUID -ne 0 ]; then
  echo "$(basename $0) must be run as root"
  exit 1
fi

dmesg --console-level 1

if [ ! -d /sys/firmware/efi/efivars ]; then
  MSG="Legacy BIOS installs are not supported. You must boot the installer in UEFI mode.\n\nWould you like to restart the computer now?"
  if (whiptail --yesno "${MSG}" 10 50); then
    reboot
  fi

  exit 1
fi


# try to set correct date & time -- required to be able to connect to github via https if your hardware clock is set too far into the past
timedatectl set-ntp true


#### Test connection or ask the user for configuration ####

# Waiting a bit because some wifi chips are slow to scan 5GHZ networks and to avoid kernel boot up messages printing over the screen
sleep 10

# TARGET="stable"
while ! (curl -Ls --http1.1 https://bing.com | grep '<html' >/dev/null); do
  whiptail \
    "未检测到互联网连接。请使用网络配置工具激活网络，然后选择 <Quit> 以退出工具并继续安装。" \
    12 50 \
    --yesno \
    --yes-button "网络配置" \
    --no-button "退出安装"

  if [ $? -ne 0 ]; then
    exit 1
  fi

  nmtui-connect
done
#######################################

MOUNT_PATH=/tmp/frzr_root

if ! frzr-bootstrap gamer; then
  whiptail --msgbox "系统引导步骤失败\n输入 ~/install.sh 可以重新开始" 10 50
  exit 1
fi

#### Post install steps for system configuration
# Copy over all network configuration from the live session to the system
SYS_CONN_DIR="/etc/NetworkManager/system-connections"
if [ -d ${SYS_CONN_DIR} ] && [ -n "$(ls -A ${SYS_CONN_DIR})" ]; then
  mkdir -p -m=700 ${MOUNT_PATH}${SYS_CONN_DIR}
  cp ${SYS_CONN_DIR}/* \
    ${MOUNT_PATH}${SYS_CONN_DIR}/.
fi

# Grab the steam bootstrap for first boot

URL="https://steamdeck-packages.steamos.cloud/archlinux-mirror/jupiter-main/os/x86_64/steam-jupiter-stable-1.0.0.79-1-x86_64.pkg.tar.zst"
TMP_PKG="/tmp/package.pkg.tar.zst"
TMP_FILE="/tmp/bootstraplinux_ubuntu12_32.tar.xz"
DESTINATION="/tmp/frzr_root/etc/first-boot/"
if [[ ! -d "$DESTINATION" ]]; then
  mkdir -p /tmp/frzr_root/etc/first-boot
fi

curl --http1.1 -# -L -o "${TMP_PKG}" -C - "${URL}" 2>&1 |
  stdbuf -oL tr '\r' '\n' | grep --line-buffered -oP '[0-9]*+(?=.[0-9])' | clean_progress 100 |
  whiptail --gauge "正在下载 Steam ..." 10 50 0

tar -I zstd -xvf "$TMP_PKG" usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz -O >"$TMP_FILE"
mv "$TMP_FILE" "$DESTINATION"
rm "$TMP_PKG"

TARGET=$(whiptail --menu "选择系统版本" 25 75 10 \
  "stable" "stable 稳定版 (GNOME) -- 默认" \
  "testing" "testing 测试版 (GNOME)" \
  "unstable" "unstable 不稳定版 (GNOME)" \
  "plasma" "plasma 稳定版 (KDE)" \
  "plasma-pre" "plasma-pre 预览版 (KDE)" \
  "plasma-dev" "plasma-dev 不稳定版 (KDE)" \
  3>&1 1>&2 2>&3)

MENU_SELECT=$(whiptail --menu "安装程序选项" 25 75 10 \
  "Standard:" "使用默认选项安装 ChimeraOS" \
  "Advanced:" "使用高级选项安装 ChimeraOS" \
  3>&1 1>&2 2>&3)

_SHOW_UI=1

firmware_overrides_opt="使用固件覆盖"
cdn_opt="CDN 加速"
fallback_opt="使用备用源"
shou_ui_opt="显示安装界面"
debug_opt="Debug 模式"

if [ "$MENU_SELECT" = "Advanced:" ]; then
  OPTIONS=$(whiptail --title "高级选项" --separate-output --checklist "使用空格键切换选中, 回车直接完成" 25 55 10 \
    "$firmware_overrides_opt" "DSDT/EDID" OFF \
    "$cdn_opt" "" OFF \
    "$fallback_opt" "" ON \
    "$shou_ui_opt" "" ON \
    "$debug_opt" "" OFF \
    3>&1 1>&2 2>&3)

  if echo "$OPTIONS" | grep -q "$firmware_overrides_opt"; then
    echo "启用固件覆盖..."
    if [[ ! -d "/tmp/frzr_root/etc/device-quirks/" ]]; then
      mkdir -p "/tmp/frzr_root/etc/device-quirks"
      # Create device-quirks default config
      cat >"/tmp/frzr_root/etc/device-quirks/device-quirks.conf" <<EOL
export USE_FIRMWARE_OVERRIDES=1
export USB_WAKE_ENABLED=1
EOL
      # Create dsdt_override.log with default values
      cat >"/tmp/frzr_root/etc/device-quirks/dsdt_override.log" <<EOL
LAST_DSDT=None
LAST_BIOS_DATE=None
LAST_BIOS_RELEASE=None
LAST_BIOS_VENDOR=None
LAST_BIOS_VERSION=None
EOL
    fi
  fi

  if echo "$OPTIONS" | grep -q "$cdn_opt"; then
    sed -i "s/^release_cdn.*/release_cdn = true/" /etc/frzr-sk.conf
    sed -i "s/^api_cdn.*/api_cdn = true/" /etc/frzr-sk.conf
  else
    sed -i "s/^release_cdn.*/release_cdn = false/" /etc/frzr-sk.conf
    sed -i "s/^api_cdn.*/api_cdn = false/" /etc/frzr-sk.conf
  fi

  if echo "$OPTIONS" | grep -q "$fallback_opt"; then
    sed -i "s/^fallback_url.*/fallback_url = true/" /etc/frzr-sk.conf
  else
    sed -i "s/^fallback_url.*/fallback_url = false/" /etc/frzr-sk.conf
  fi

  if echo "$OPTIONS" | grep -q "$shou_ui_opt"; then
    _SHOW_UI=1
  else
    _SHOW_UI=""
  fi

  if echo "$OPTIONS" | grep -q "$debug_opt"; then
    export DEBUG=1
  fi
fi

export SHOW_UI="${_SHOW_UI}"

if (ls -1 /dev/disk/by-label | grep -q FRZR_UPDATE); then

  CHOICE=$(whiptail --menu "你想如何安装ChimeraOS ?" 18 50 10 \
    "local" "使用本地媒介行安装." \
    "online" "在线获取最新系统镜像." \
    3>&1 1>&2 2>&3)
fi

export NOT_UMOUNT=true

if [ "${CHOICE}" == "local" ]; then
  export local_install=true
  frzr-deploy | tee /tmp/frzr.log
  # bash 管道执行命令后，获取命令的返回值 ，从 PIPESTATUS[0] 开始
  # zsh 则是从 pipestatus[1] 开始
  RESULT=${PIPESTATUS[0]}
else
  frzr-deploy "3003n/chimeraos:${TARGET}" | tee /tmp/frzr.log
  RESULT=${PIPESTATUS[0]}
fi

MSG="安装失败."
if [ "${RESULT}" == "0" ]; then
  BOOT_CFG="${MOUNT_PATH}/boot/loader/entries/frzr.conf"
  if [[ ! -f "${BOOT_CFG}" ]]; then
    if [[ -n "$BOOT_CFG_PARA" ]]; then
      echo "${BOOT_CFG_PARA}" > "${BOOT_CFG}"
      echo "default frzr.conf" > "${MOUNT_PATH}/boot/loader/loader.conf"
    else
      MSG="安装失败. 未找到启动配置文件."
    fi
  else
    MSG="安装成功完成"
  fi
elif [ "${RESULT}" == "29" ]; then
  MSG="遇到 GitHub API 速率限制错误, 请稍后重试安装"
else
  fpaste_url=$(fpaste /tmp/frzr.log 2>/dev/null)
  if [ -n "${fpaste_url}" ]; then
    fpaste_msg="日志已上传至 ${fpaste_url}"
  fi
  MSG="安装失败. 请检查 /tmp/frzr.log 文件以获取更多信息. ${fpaste_msg}"
fi

echo -e "${MSG} RESULT:${RESULT}\n\n"

if (whiptail --yesno "${MSG} RESULT:${RESULT}\n\n立即重启?" 10 50); then
  reboot
fi

exit ${RESULT}
