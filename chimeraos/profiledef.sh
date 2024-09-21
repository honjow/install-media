#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="sk-chimeraos"
iso_label="SK-CHIMERAOS_$(date +%Y%m)"
iso_publisher="Sk-ChimeraOS <https://github.com/ChimeraOS>"
iso_application="Sk ChimeraOS Installer"
iso_version=$(date +%Y.%m.%d)
install_dir="arch"
buildmodes=('iso')
bootmodes=('uefi-x64.systemd-boot.esp' 'uefi-x64.systemd-boot.eltorito')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/root/install.sh"]="0:0:755"
  ["/root/probe.sh"]="0:0:755"
  ["/root/.automated_script.sh"]="0:0:755"
  ["/usr/bin/__frzr-deploy"]="0:0:755"
  ["/usr/bin/frzr-bootstrap"]="0:0:755"
  ["/usr/bin/frzr-deploy"]="0:0:755"
  ["/usr/bin/frzr-initramfs"]="0:0:755"
  ["/usr/bin/frzr-release"]="0:0:755"
  ["/usr/bin/frzr-tweaks"]="0:0:755"
  ["/usr/local/bin/choose-mirror"]="0:0:755"
  ["/usr/local/bin/Installation_guide"]="0:0:755"
  ["/usr/local/bin/livecd-sound"]="0:0:755"
)
