Default [raspbian installation images](https://www.raspberrypi.org/downloads/raspbian/) are formated to ext4. Some people believe that f2fs filesystem would be a better choice.

The [official way](https://www.raspberrypi.org/forums/viewtopic.php?f=29&t=47769) to convert the filesystem involves juggling 2 sd cards, booting the raspberry pi from usb and a lot of other manual steps. I have never actually performed in but it looks like it takes a lot of time and effort.

Introducing a new

# script to automatically convert raspbian installation image to f2fs

The script performs the following:

 - download the installation image
 - convert the image filesystem to f2fs
 - perform raspbian tweaks to be able to boot from f2fs root
 - write the image to an sd card
 - resize the sd card root partition and f2fs filesystem to fill 100% of the card

# quick instructions
Disable automatic mounting:

    gsettings set org.gnome.desktop.media-handling automount false
    
Download the script:

    git clone https://github.com/r0b0/rebuild_raspbian_f2fs.git
    
Insert the sd card to the PC and run the script:

    cd rebuild_raspbian_f2fs
    sudo ./rebuild_raspbian_f2fs
    
Optionally re-enable automount:
    gsettings set org.gnome.desktop.media-handling automount true
    
# requirements
The script has been sucessfully tested on Debian 9 (stretch) and Debian 8 (jessie) with backports enabled. Let me know if it works for you on other platforms.

