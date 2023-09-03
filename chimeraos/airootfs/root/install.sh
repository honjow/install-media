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
     "未检测到互联网连接-No internet connection detected.\n\nPlease use the network configuration tool to activate a network, then select \"Quit\" to exit the tool and continue the installation." \
     12 50 \
     --yesno \
     --yes-button "Configure" \
     --no-button "Exit"

    if [ $? -ne 0 ]; then
         exit 1
    fi

    nmtui-connect
done
#######################################

MOUNT_PATH=/tmp/frzr_root

if ! frzr-bootstrap gamer; then
    whiptail --msgbox "System bootstrap step failed." 10 50
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

MENU_SELECT=$(whiptail --menu "Installer Options" 25 75 10 \
  "Standard Install" "Install ChimeraOS with default options." \
  "Advanced Install" "Install ChimeraOS with advanced options." \
   3>&1 1>&2 2>&3)

if [ "$MENU_SELECT" = "Advanced Install" ]; then
  OPTIONS=$(whiptail --separate-output --checklist "Choose options" 10 55 4 \
    "Use Firmware Overrides" "DSDT/EDID" OFF \
    "Unstable Builds" "" OFF 3>&1 1>&2 2>&3)

  if echo "$OPTIONS" | grep -q "Use Firmware Overrides"; then
    echo "Enabling firmware overrides..."
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

  if echo "$OPTIONS" | grep -q "Unstable Builds"; then
    TARGET="unstable"
  fi
fi


export SHOW_UI=1

if ( ls -1 /dev/disk/by-label | grep -q FRZR_UPDATE ); then

CHOICE=$(whiptail --menu "How would you like to install ChimeraOS?" 18 50 10 \
  "local" "Use local media for installation." \
  "online" "Fetch the latest stable image." \
   3>&1 1>&2 2>&3)
fi

if [ "${CHOICE}" == "local" ]; then
    export local_install=true
    frzr-deploy
    RESULT=$?
else
    frzr-deploy honjow/chimeraos:${TARGET}
    RESULT=$?
fi

MSG="Installation failed."
if [ "${RESULT}" == "0" ]; then
    MSG="Installation successfully completed."
elif [ "${RESULT}" == "29" ]; then
    MSG="GitHub API rate limit error encountered. Please retry installation later."
fi

if (whiptail --yesno "${MSG}\n\nWould you like to restart the computer now?" 10 50); then
    reboot
fi

exit ${RESULT}
