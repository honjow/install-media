#! /bin/bash

set -o pipefail

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

poll_gamepad() {
        modprobe xpad > /dev/null
        systemctl start inputplumber > /dev/null

        while true; do
                sleep 1
                busctl call org.shadowblip.InputPlumber \
                        /org/shadowblip/InputPlumber/CompositeDevice0 \
                        org.shadowblip.Input.CompositeDevice \
                        LoadProfilePath "s" /root/gamepad_profile.yaml &> /dev/null
                if [ $? == 0 ]; then
                        break
                fi
        done
}

get_boot_disk() {
        local current_boot_id=$(efibootmgr | grep BootCurrent | head -1 | cut -d':' -f 2 | tr -d ' ')
        local boot_disk_info=$(efibootmgr | grep "Boot${current_boot_id}" | head -1)
        local part_uuid=$(echo $boot_disk_info | tr "/" "\n" | grep "HD(" | cut -d',' -f3 | head -1 | sed -e 's/^0x//')

        if [ -z $part_uuid ]; then
                # prevent printing errors when the boot disk info is not in a known format
                return
        fi

        local part=$(blkid | grep $part_uuid | cut -d':' -f1 | head -1 | sed -e 's,/dev/,,')
        local part_path=$(readlink "/sys/class/block/$part")
        basename `dirname $part_path`
}

is_disk_external() {
        local disk=$1     # the disk to check if it is external
        local external=$(lsblk --list -n -o name,hotplug | grep "$disk " | cut -d' ' -f2- | xargs echo -n)

        test "$external" == "1"
}

is_disk_smaller_than() {
        local disk=$1     # the disk to check the size of
        local min_size=$2 # minimum size in GB
        local size=$(lsblk --list -n -o name,size | grep "$disk " | cut -d' ' -f2- | xargs echo -n)

        if echo $size | grep "T$" &> /dev/null; then
                return 1
        fi

        if echo $size | grep "G$" &> /dev/null; then
                size=$(echo $size | sed 's/G//' | cut -d'.' -f1)
                if [ "$size" -lt "$min_size" ]; then
                        return 0
                else
                        return 1
                fi
        fi

        return 0
}

get_disk_model_override() {
        local device=$1
        grep "${DEVICE_VENDOR}:${DEVICE_PRODUCT}:${DEVICE_CPU}:${device}" overrides | cut -f2- | xargs echo -n
}

get_disk_human_description() {
        local name=$1
        local size=$(lsblk --list -n -o name,size | grep "$name " | cut -d' ' -f2- | xargs echo -n)

        if [ "$size" = "0B" ]; then
                return
        fi

        local model=$(get_disk_model_override $name | xargs echo -n)
        if [ -z "$model" ]; then
                model=$(lsblk --list -n -o name,model | grep "$name " | cut -d' ' -f2- | xargs echo -n)
        fi

        local vendor=$(lsblk --list -n -o name,vendor | grep "$name " | cut -d' ' -f2- | xargs echo -n)
        local transport=$(lsblk --list -n -o name,tran | grep "$name " | cut -d' ' -f2- | \
                sed -e 's/usb/USB/' | \
                sed -e 's/nvme/Internal/' | \
                sed -e 's/sata/Internal/' | \
                sed -e 's/ata/Internal/' | \
                sed -e 's/mmc/SD card/' | \
                xargs echo -n)
        echo "[${transport}] ${vendor} ${model:=Unknown model} ($size)" | xargs echo -n
}

cancel_install() {
    if (whiptail --yesno --yes-button "Power off" --no-button "Open command prompt" "Installation was cancelled. What would you like to do?" 10 70); then
        poweroff
    fi

    exit 1
}

select_disk() {
    while true
    do
            # a key/value store using an array
            # even number indexes are keys (starting at 0), odd number indexes are values
            # keys are the disk name without `/dev` e.g. sda, nvme0n1
            # values are the disk description
            device_list=()

            boot_disk=$(get_boot_disk)
            if [ -n "$boot_disk" ]; then
                    device_output=$(lsblk --list -n -o name,type | grep disk | grep -v zram | grep -v $boot_disk)
            else
                    device_output=$(lsblk --list -n -o name,type | grep disk | grep -v zram)
            fi

            while read -r line; do
                    name=$(echo "$line" | cut -d' ' -f1 | xargs echo -n)
                    description=$(get_disk_human_description $name)
                    if [ -z "$description" ]; then
                            continue
                    fi
                    device_list+=($name)
                    device_list+=("$description")
            done <<< "$device_output"

            # NOTE: each disk entry consists of 2 elements in the array (disk name & disk description)
            if [ "${#device_list[@]}" -gt 2 ]; then
                    export DISK=$(whiptail --nocancel --menu "Choose a disk to install $OS_NAME on:" 20 70 5 "${device_list[@]}" 3>&1 1>&2 2>&3)
            elif [ "${#device_list[@]}" -eq 2 ]; then
                    # skip selection menu if only a single disk is available to choose from
                    export DISK=${device_list[0]}
            else
                    whiptail --msgbox "Could not find a disk to install to.\n\nPlease connect a 64 GB or larger disk and start the installer again." 12 70
                    cancel_install
            fi

            export DISK_DESC=$(get_disk_human_description $DISK)

            if is_disk_smaller_than $DISK $MIN_DISK_SIZE; then
                    if (whiptail --yesno --yes-button "Select a different disk" --no-button "Cancel install" \
                            "ERROR: The selected disk $DISK - $DISK_DESC is too small. $OS_NAME requires at least $MIN_DISK_SIZE GB.\n\nPlease select a different disk." 12 75); then
                            continue
                    else
                            cancel_install
                    fi
            fi

            if is_disk_external $DISK; then
                    if (whiptail --yesno --defaultno --yes-button "Install anyway" --no-button "Select a different disk" \
                            "WARNING: $DISK - $DISK_DESC appears to be an external disk. Installing $OS_NAME to an external disk is not officially supported and may result in poor performance and permanent damage to the disk.\n\nDo you wish to install anyway?" 12 80); then
                            break
                    else
                            # Unlikely that we would ever have ONLY an external disk, so this should be good enough
                            continue
                    fi
            fi

            break
    done
}




if [ $EUID -ne 0 ]; then
  echo "$(basename $0) must be run as root"
  exit 1
fi


OS_NAME=ChimeraOS
MIN_DISK_SIZE=55 # GB

DEVICE_VENDOR=$(cat /sys/devices/virtual/dmi/id/sys_vendor)
DEVICE_PRODUCT=$(cat /sys/devices/virtual/dmi/id/product_name)
DEVICE_CPU=$(lscpu | grep Vendor | cut -d':' -f2 | xargs echo -n)



dmesg --console-level 1



# start polling for a gamepad
poll_gamepad &


# try to set correct date & time -- required to be able to connect to github via https if your hardware clock is set too far into the past
timedatectl set-ntp true

#### Test connection or ask the user for configuration ####

# Waiting a bit because some wifi chips are slow to scan 5GHZ networks
echo "Starting installer..."
sleep 2

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

# sets DISK and DISK_DESC
select_disk

# warn before erasing disk
if ! (whiptail --yesno --defaultno --yes-button "Erase disk and install" --no-button "Cancel install" "\
WARNING: $OS_NAME will now be installed and all data on the following disk will be lost:\n\n\
        $DISK - $DISK_DESC\n\n\
Do you wish to proceed?" 15 70); then
        cancel_install
fi

# perform bootstrap of disk
if ! frzr-bootstrap gamer /dev/${DISK}; then
  whiptail --msgbox "系统引导步骤失败\n输入 ~/install.sh 可以重新开始" 10 50
  cancel_install
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

# URL="https://steamdeck-packages.steamos.cloud/archlinux-mirror/jupiter-main/os/x86_64/steam-jupiter-stable-1.0.0.79-1.1-x86_64.pkg.tar.zst"
# TMP_PKG="/tmp/package.pkg.tar.zst"
STM_PKG="/root/packages/steam-jupiter-stable.pkg.tar.zst"
TMP_FILE="/tmp/bootstraplinux_ubuntu12_32.tar.xz"
DESTINATION="/tmp/frzr_root/etc/first-boot/"
if [[ ! -d "$DESTINATION" ]]; then
  mkdir -p /tmp/frzr_root/etc/first-boot
fi

# curl --http1.1 -# -L -o "${TMP_PKG}" -C - "${URL}" 2>&1 |
#   stdbuf -oL tr '\r' '\n' | grep --line-buffered -oP '[0-9]*+(?=.[0-9])' | clean_progress 100 |
#   whiptail --gauge "正在下载 Steam ..." 10 50 0

tar -I zstd -xvf "$STM_PKG" usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz -O >"$TMP_FILE"
mv "$TMP_FILE" "$DESTINATION"
# rm "$TMP_PKG"

TARGET=$(whiptail --menu "选择系统版本" 25 75 10 \
  "stable"            "stable 稳定版 (GNOME) -- 默认" \
  "testing"           "testing 测试/预览版 (GNOME)" \
  "unstable"          "unstable 不稳定/开发版 (GNOME)" \
  "plasma"            "plasma 稳定版 (KDE)" \
  "plasma-pre"        "plasma-pre 测试/预览版版 (KDE)" \
  "plasma-dev"        "plasma-dev 开发版 (KDE)" \
  "gnome_nvidia"      "gnome_nvidia 稳定版 (GNOME NVIDIA)" \
  "gnome_nvidia-pre"  "gnome_nvidia-pre 测试/预览版版 (GNOME NVIDIA)" \
  "gnome_nvidia-dev"  "gnome_nvidia-dev 不稳定/开发版 (GNOME NVIDIA)" \
  "plasma_nvidia"     "plasma_nvidia 稳定版 (KDE NVIDIA)" \
  "plasma_nvidia-pre" "plasma_nvidia-pre 测试/预览版版 (KDE NVIDIA)" \
  "plasma_nvidia-dev" "plasma_nvidia-dev 不稳定/开发版 (KDE NVIDIA)" \
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
      echo "${BOOT_CFG_PARA}" >"${BOOT_CFG}"
      echo "default frzr.conf" >"${MOUNT_PATH}/boot/loader/loader.conf"
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

if [ "$SHOW_UI" == "1" ]; then
  if (whiptail --yesno "${MSG} RESULT:${RESULT}\n\n立即重启?" 10 50); then
    reboot
  fi
else
  # 命令行显示错误信息，提示用户查看日志。检测用户输入，y重启，n退出，r执行 ~/install.sh 重新安装
  echo -e "${MSG} RESULT:${RESULT}\n\n立即重启? (y/n/r)"
  read -r -n 1 -s -t 60 -p "立即重启? (y/n/r)" input
  echo
  case $input in
  [yY])
    reboot
    ;;
  [nN])
    exit 1
    ;;
  [rR])
    ~/install.sh
    ;;
  *)
    echo "无效输入"
    ;;
  esac
fi

exit ${RESULT}
