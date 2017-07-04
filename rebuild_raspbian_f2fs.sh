#!/bin/bash

RASPBIAN_LINK=https://downloads.raspberrypi.org/raspbian_lite_latest

# crash on error
set -e

# only run as root
if [[ $EUID -ne 0 ]]; then
	echo "Please run this as root"
	exit 1
fi

# install necessary tools
apt-get install -y curl unzip kpartx f2fs-tools rsync qemu-user-static

# download image
if [[ ! -f raspbian_lite_latest.zip ]]; then
	curl -L -o raspbian_lite_latest.zip $RASPBIAN_LINK
fi

ORIG_IMAGE=$(unzip -qql raspbian_lite_latest.zip | tr -s ' '|cut -f 4 -d ' ')
TARGET_IMAGE="$(basename $ORIG_IMAGE .img).f2fs.img"
echo "Working on $ORIG_IMAGE -> $TARGET_IMAGE"

if [[ ! -f $ORIG_IMAGE ]]; then
	unzip raspbian_lite_latest.zip
fi

if [[ ! -f $TARGET_IMAGE ]]; then
	cp -f $ORIG_IMAGE $TARGET_IMAGE
fi

# remove dangling partitions
kpartx -d $ORIG_IMAGE
kpartx -d $TARGET_IMAGE

# re-map the partitions
ORIG_DEVS=($(kpartx -avs $ORIG_IMAGE | cut -f 3 -d ' '))
TARGET_DEVS=($(kpartx -avs $TARGET_IMAGE | cut -f 3 -d ' '))
ORIG_ROOT_DEV="/dev/mapper/${ORIG_DEVS[1]}"
TARGET_BOOT_DEV="/dev/mapper/${TARGET_DEVS[0]}"
TARGET_ROOT_DEV="/dev/mapper/${TARGET_DEVS[1]}"

ls -la $ORIG_ROOT_DEV $TARGET_ROOT_DEV $TARGET_BOOT_DEV

# format target root device to f2fs
mkfs.f2fs $TARGET_ROOT_DEV

# create directory structure for mounts
if [[ ! -d target ]]; then
	mkdir target
fi

if [[ ! -d orig ]]; then
	mkdir orig
fi

# mount roots
mount $TARGET_ROOT_DEV target
mount $ORIG_ROOT_DEV orig

# copy root
rsync -axv orig/ target

# umount orig
umount $ORIG_ROOT_DEV

# copy over qemu arm
cp /usr/bin/qemu-arm-static target/usr/bin/

# mount boot
mount $TARGET_BOOT_DEV target/boot

# tweak the image for f2fs
chroot target/ apt-get install -y f2fs-tools
chroot target/ update-initramfs -u
chroot target/ sed -i 's/rootfstype=ext4/rootfstype=f2fs/' /boot/cmdline.txt

# remove qemu arm from target
rm -f target/usr/bin/qemu-arm-static 

umount $TARGET_BOOT_DEV
umount $TARGET_ROOT_DEV

kpartx -d $ORIG_IMAGE
kpartx -d $TARGET_IMAGE

echo "Please find f2fs raspbian image in:"
ls -lh $TARGET_IMAGE

