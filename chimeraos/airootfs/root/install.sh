#! /bin/bash

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


#### Test conenction or ask the user for configuration ####

# Waiting a bit because some wifi chips are slow to scan 5GHZ networks
sleep 2

TARGET="stable"
while ! ( curl -Ls https://github.com | grep '<html' > /dev/null ); do
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
    whiptail --msgbox "系统引导步骤失败\n输入 ./install.sh 可以重新开始" 10 50
    exit 1
fi

#### Post install steps for system configuration
# Copy over all network configuration from the live session to the system
SYS_CONN_DIR="/etc/NetworkManager/system-connections"
if [ -d ${SYS_CONN_DIR} ] && [ -n "$(ls -A ${SYS_CONN_DIR})" ]; then
    mkdir -p -m=700 ${MOUNT_PATH}${SYS_CONN_DIR}
    cp  ${SYS_CONN_DIR}/* \
        ${MOUNT_PATH}${SYS_CONN_DIR}/.
fi

# Grab the steam bootstrap for first boot

URL="https://steamdeck-packages.steamos.cloud/archlinux-mirror/jupiter-main/os/x86_64/steam-jupiter-stable-1.0.0.76-1-x86_64.pkg.tar.zst"
TMP_PKG="/tmp/package.pkg.tar.zst"
TMP_FILE="/tmp/bootstraplinux_ubuntu12_32.tar.xz"
DESTINATION="/tmp/frzr_root/etc/first-boot/"
if [[ ! -d "$DESTINATION" ]]; then
      mkdir -p /tmp/frzr_root/etc/first-boot
fi

curl -o "$TMP_PKG" "$URL"
tar -I zstd -xvf "$TMP_PKG" usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz -O > "$TMP_FILE"
mv "$TMP_FILE" "$DESTINATION"
rm "$TMP_PKG"

MENU_SELECT=$(whiptail --menu "安装程序选项" 25 75 10 \
  "Standard Install" "使用默认选项安装 ChimeraOS" \
  "Advanced Install" "使用高级选项安装 ChimeraOS" \
   3>&1 1>&2 2>&3)

firmware_overrides_keyword="使用固件覆盖"
unstable_keyword="Unstable 不稳定构建"
cdn_keyword="CDN 加速"
fallback_keyword="使用备用源"

if [ "$MENU_SELECT" = "Advanced Install" ]; then
  OPTIONS=$(whiptail --separate-output --checklist "Choose options" 10 55 4 \
    "$firmware_overrides_keyword" "DSDT/EDID" OFF \
    "$unstable_keyword" "" OFF 3>&1 1>&2 2>&3)

  if echo "$OPTIONS" | grep -q "$firmware_overrides_keyword"; then
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

  if echo "$OPTIONS" | grep -q "$unstable_keyword"; then
    TARGET="unstable"
  fi

  if echo "$OPTIONS" | grep -q "$cdn_keyword"; then
    sed -i "s/^release_cdn.*/release_cdn = true/" /etc/frzr-sk.conf
    sed -i "s/^api_cdn.*/api_cdn = true/" /etc/frzr-sk.conf
  fi

  if echo "$OPTIONS" | grep -q "$fallback_keyword"; then
    sed -i "s/^fallback_url.*/fallback_url = true/" /etc/frzr-sk.conf
  fi

fi


export SHOW_UI=1

if ( ls -1 /dev/disk/by-label | grep -q FRZR_UPDATE ); then

CHOICE=$(whiptail --menu "你想如何安装ChimeraOS ?" 18 50 10 \
  "local" "使用本地媒介行安装." \
  "online" "在线获取最新系统镜像." \
   3>&1 1>&2 2>&3)
fi

if [ "${CHOICE}" == "local" ]; then
    export local_install=true
    frzr-deploy
    RESULT=$?
else
    frzr-deploy "3003n/chimeraos:${TARGET}"
    RESULT=$?
fi

MSG="安装失败."
if [ "${RESULT}" == "0" ]; then
    MSG="安装成功完成"
elif [ "${RESULT}" == "29" ]; then
    MSG="遇到 GitHub API 速率限制错误, 请稍后重试安装"
fi

if (whiptail --yesno "${MSG}\n\n立即重启?" 10 50); then
    reboot
fi

exit ${RESULT}
