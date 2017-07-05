#!/bin/bash

RASPBIAN_LINK=https://downloads.raspberrypi.org/raspbian_lite_latest

function cleanup {
	set +e
	sync
	umount orig
	umount target
	kpartx -d *.img
	sleep 1
	kpartx -d *.img
}

# crash on error
set -e
trap cleanup EXIT

# only run as root
if [[ $EUID -ne 0 ]]; then
	echo "Please run this as root"
	exit 1
fi

echo "Installing necessary tools"
apt-get install -y curl unzip kpartx f2fs-tools rsync qemu-user-static

if [[ ! -f raspbian_lite_latest.zip ]]; then
	echo "Downloading installation image"
	curl -L -o raspbian_lite_latest.zip $RASPBIAN_LINK
fi

ORIG_IMAGE=$(unzip -qql raspbian_lite_latest.zip | tr -s ' '|cut -f 4 -d ' ')
TARGET_IMAGE="$(basename $ORIG_IMAGE .img).f2fs.img"
echo "Working on $ORIG_IMAGE -> $TARGET_IMAGE"

if [[ ! -f $ORIG_IMAGE ]]; then
	echo "Uncompressing installation image"
	unzip raspbian_lite_latest.zip
fi

if [[ ! -f $TARGET_IMAGE ]]; then
	echo "Creating target image"
	cp -f $ORIG_IMAGE $TARGET_IMAGE
fi

# echo "Removing dangling partitions"
# set +e
# kpartx -d $ORIG_IMAGE
# kpartx -d $TARGET_IMAGE
# set -e

echo "Mapping the image partitions to loopkack devices"
ORIG_DEVS=($(kpartx -avs $ORIG_IMAGE | cut -f 3 -d ' '))
TARGET_DEVS=($(kpartx -avs $TARGET_IMAGE | cut -f 3 -d ' '))
ORIG_ROOT_DEV="/dev/mapper/${ORIG_DEVS[1]}"
TARGET_BOOT_DEV="/dev/mapper/${TARGET_DEVS[0]}"
TARGET_ROOT_DEV="/dev/mapper/${TARGET_DEVS[1]}"

ls -la $ORIG_ROOT_DEV $TARGET_ROOT_DEV $TARGET_BOOT_DEV

echo "Checking filesystem type of $TARGET_ROOT_DEV"
ROOTDEV_FSTYPE=$(blkid -o value -s TYPE $TARGET_ROOT_DEV)

if [[ $ROOTDEV_FSTYPE == "f2fs" ]]; then
	echo "Already formated to f2fs"
else
	echo "Formating target root device to f2fs"
	mkfs.f2fs $TARGET_ROOT_DEV
fi

# create directory structure for mounts
if [[ ! -d target ]]; then
	mkdir target
fi

if [[ ! -d orig ]]; then
	mkdir orig
fi

echo "Mounting roots"
mount $TARGET_ROOT_DEV target
mount $ORIG_ROOT_DEV orig

echo "Copying root"
rsync -ax orig/ target

echo "Unmounting orig image"
sync
sleep 2
umount $ORIG_ROOT_DEV

echo "Copying over qemu arm"
cp /usr/bin/qemu-arm-static target/usr/bin/

echo "Mounting boot"
mount $TARGET_BOOT_DEV target/boot

echo "Tweaking the image for f2fs"
chroot target/ apt-get install -y f2fs-tools
# chroot target/ update-initramfs -u
chroot target/ sed -i 's/rootfstype=ext4/rootfstype=f2fs/' /boot/cmdline.txt
chroot target/ sed -i 's/ext4/f2fs/' /etc/fstab

echo "Removing qemu arm from target"
rm -f target/usr/bin/qemu-arm-static 

echo "Umounting images"
umount $TARGET_BOOT_DEV
umount $TARGET_ROOT_DEV

echo "Unmapping images from loopback"
set +e # this fails me sometimes
sleep 1
kpartx -d $ORIG_IMAGE
kpartx -d $TARGET_IMAGE
sleep 1
kpartx -d *.img
set -e

echo "F2fs raspbian image created in:"
ls -lh $TARGET_IMAGE

read -p "Enter device name of sd card: " SD_DEVICE
ls $SD_DEVICE

echo "Checking if $SD_DEVICE is a usb device"
set +e
readlink -f /dev/disk/by-path/*usb* |grep -q $SD_DEVICE

if [[ $? -ne 0 ]]; then
	echo "Failed safety check - $SD_DEVICE does not appear to be a usb device"
	exit 2
fi
set -e

read -p "Going to overwrite $SD_DEVICE, press Enter to confirm, Ctrl+C to abort" dummy

echo "Writing $TARGET_IMAGE to $SD_DEVICE"
dd if=$TARGET_IMAGE of=$SD_DEVICE bs=4MB conv=fsync

echo "Re-reading partition table of $SD_DEVICE"
partprobe $SD_DEVICE

echo "Resizing root partition of $SD_DEVICE to fill 100%"
echo ",+" |sfdisk --force -N 2 $SD_DEVICE

echo "Re-reading partition table of $SD_DEVICE"
sync
sleep 2
partprobe $SD_DEVICE
sleep 2

echo "Resizing filesystem of the root partition"
resize.f2fs ${SD_DEVICE}2

echo "All done."

