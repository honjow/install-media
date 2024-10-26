#! /bin/bash

vendor=$(cat /sys/devices/virtual/dmi/id/sys_vendor)
product_name=$(cat /sys/devices/virtual/dmi/id/product_name)
cpu_vendor=$(lscpu | grep Vendor | cut -d':' -f2 | xargs echo -n)

echo "Vendor: $vendor"
echo "Product name: $product_name"
echo "CPU vendor: $cpu_vendor"

device_output=$(lsblk --list -n -o name,type | grep disk)
while read -r line; do
        name=$(echo "$line" | cut -d' ' -f1 | xargs echo -n)
        size=$(lsblk --list -n -o name,size       | grep "$name " | cut -d' ' -f2- | xargs echo -n)
        vendor=$(lsblk --list -n -o name,vendor   | grep "$name " | cut -d' ' -f2- | xargs echo -n)
        model=$(lsblk --list -n -o name,model     | grep "$name " | cut -d' ' -f2- | xargs echo -n)
        hotplug=$(lsblk --list -n -o name,hotplug | grep "$name " | cut -d' ' -f2- | xargs echo -n)
        removable=$(lsblk --list -n -o name,rm    | grep "$name " | cut -d' ' -f2- | xargs echo -n)
        transport=$(lsblk --list -n -o name,tran  | grep "$name " | cut -d' ' -f2- | xargs echo -n)

	echo "========== Storage =========="
	echo "Name: $name"
	echo "Size: $size"
	echo "Vendor: $vendor"
	echo "Model: $model"
	echo "Hotplug: $hotplug"
	echo "Removable: $removable"
	echo "Transport: $transport"
done <<< "$device_output"

