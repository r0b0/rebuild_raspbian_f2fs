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
apt-get install -y curl unzip kpartx f2fs-tools

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
ORIG_DEVS=($(kpartx -av $ORIG_IMAGE | cut -f 3 -d ' '))
TARGET_DEVS=($(kpartx -av $TARGET_IMAGE | cut -f 3 -d ' '))
ORIG_BOOT_DEV="/dev/mapper/${ORIG_DEVS[0]}"
ORIG_ROOT_DEV="/dev/mapper/${ORIG_DEVS[1]}"
TARGET_BOOT_DEV="/dev/mapper/${TARGET_DEVS[0]}"
TARGET_ROOT_DEV="/dev/mapper/${TARGET_DEVS[1]}"
echo "Orig devices: $ORIG_BOOT_DEV, $ORIG_ROOT_DEV"
echo "Target devices: $TARGET_BOOT_DEV, $TARGET_ROOT_DEV"

# format target root device to f2fs
mkfs.f2fs $TARGET_ROOT_DEV

# mount the devices
if [[ ! -d target ]]; then
	mkdir target
fi

if [[ ! -d target/boot ]]; then
	mkdir target/boot
fi

if [[ ! -d orig ]]; then
	mkdir orig
fi

mount $TARGET_ROOT_DEV target
mount $ORIG_ROOT_DEV orig


