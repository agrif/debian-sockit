#!/bin/bash

# where are we?
installsh=$0
scriptpath="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
scriptpid=$$

# make sure we have GNU getopt
getopt --test > /dev/null
if [[ $? != 4 ]]; then
    echo "$installsh: GNU getopt not found"
    exit 3
fi

# FIXME check for tools

# our command line options
SHORTOPTS=vs:y
LONGOPTS=verbose,step:,yes,menuconfig

# general options
verbose=0
step=0
autoconfirm=0
menuconfig=0

# filesystem options
BOOTLABEL="BOOT INFO"
ROOTLABEL="Debian Jessie"
MOUNTPOINT="mnt"

# kernel options
KERNELTAG="ACDS13.1_REL_GSRD_PR"
KERNELGIT="https://github.com/altera-opensource/linux-socfpga.git"
KERNELDIR="linux-socfpga"
KERNELCROSS="arm-linux-gnueabihf-"
KERNELDTB="socfpga_cyclone5.dtb"

# debian options
CODENAME="jessie"
MIRROR="http://ftp.us.debian.org/debian/"
SECMIRROR="http://security.debian.org/"
USERNAME="sockit"
PASSWORD="arrow"
HOSTNAME="sockit"
TIMEZONE="US/Eastern"
LOCALE="en_US.UTF-8"

# parse command line
OPTS=`getopt --options $SHORTOPTS --longoptions $LONGOPTS --name "$installsh" -- "$@"`
if [[ $? != 0 ]]; then
    exit 5
fi

# get results
eval set -- "$OPTS"

# parse results
while true; do
    case "$1" in
        -v|--verbose)
            verbose=1
            shift
            ;;
        -s|--step)
            step="$2"
            shift 2
            ;;
        -y|--yes)
            autoconfirm=1
            shift
            ;;
        --menuconfig)
            menuconfig=1
            shift
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "$installsh: Unknown option: $1"
            exit 6
            ;;
    esac
done

# handle non-option arguments
if [[ $# != 1 ]]; then
    echo "$installsh: need a path to the device to install on"
    exit 7
fi
dev="$1"

# make sure we're root
if [[ $EUID != 0 ]]; then
    echo "$installsh: you are not root"
    exit 4
fi

# make sure our device is really a device
if [ ! -b "$dev" ]; then
    echo "$installsh: $dev not a block device"
    exit 8
fi

# we want to continue, yes?
echo "Installing Debian Jessie on $dev:"
echo " - using $(pwd) as scratch space"
if [[ $step != 0 ]]; then
    echo " - starting from step $step"
fi
echo "This will destroy all data on the device."
if [[ $autoconfirm == 0 ]]; then
    read -p "Are you sure you want to proceed? (y/N)? " -n 1 continue
    echo ""
    case "$continue" in
        y|Y) ;;
        n|N) echo "aborting."; exit 1;;
        *)   echo "aborting."; exit 1;;
    esac
fi

# announce a step, if we're doing it
step() {
    test "$1" -ge "$step" && echo "" && echo "[$1]: $2" && step="$1"
}

# run a command quietly (unless verbose, or unless it fails)
run_quiet() {
    local tmp=$(mktemp) || return
    echo "      - $@"
    if [[ $verbose == 1 ]]; then
        "$@"
        local result=$?
    else
        "$@" > "$tmp" 2>&1
        local result=$?
    fi
    if [[ $result != 0 ]]; then
        if [ -f "$tmp" ]; then
            cat "$tmp"
            rm -f "$tmp"
        fi
        echo ""
        echo "$installsh: command failed: $@"
        echo "$installsh: failed at step $step"
        kill -s TERM $scriptpid
    fi
    rm -f "$tmp"
    return 0
}

# catch the signal from above
trap "umount $MOUNTPOINT; exit 1" TERM

# get the path to the n'th partition of a device
partition() {
    local part="$2"
    lsblk -lpno NAME "$1" | sed "$((part+1))q;d"
}

# get the path to a data file alongside the script
datafile() {
    echo `dirname $scriptpath`/$1
}

# make with an ARM flavor
armmake() {
    make CROSS_COMPILE="$KERNELCROSS" ARCH=arm "$@"
}

# get the kernel debian version string
kerneldeb() {
    (cd "$KERNELDIR" && echo `make kernelversion`-g`git rev-parse --short HEAD`)
}

# get the number of processors
numprocs() {
    grep -c '^processor' /proc/cpuinfo
}

##
## Guide begins here.
##

# preparing the sd card
if step 11 "Preparing the SD Card - Partitioning"; then
    sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | run_quiet fdisk "$dev"
        o     # create a new DOS partition table
        n     # new partition (for bootloader)
        p     # primary
        3     # third slot
        2048  # start at sector 2048
        +2048 # make it 2048 sectors long
        t     # change the type of our new partition
        a2    # 0xA2 is our special bootleader type
        n     # new partition (for boot info)
        p     # primary
        1     # first slot
              # accept default for start
        +128M # give it 128MiB
        t     # change the type of our new partition
        1     # that is, partition 1
        0b    # mark it as W95 FAT32
        n     # new partition (root)
        p     # primary
        2     # second slot
              # accept default for start
              # accept default for end
        p     # print it out, make sure it looks about right
        w     # write changes to disk (cannot be undone)
        q     # quit fdisk
EOF
fi

if step 12 "Preparing the SD Card - Formatting"; then
    run_quiet mkfs.vfat -n "$BOOTLABEL" `partition "$dev" 1`
    run_quiet mkfs.ext4 -L "$ROOTLABEL" `partition "$dev" 2`
    run_quiet dd if=`datafile uboot.img` of=`partition "$dev" 3` bs=4k
fi

if step 21 "Building a Kernel - Cloning"; then
    if [ ! -d "$KERNELDIR" ]; then
        run_quiet git clone --depth=1 -b "$KERNELTAG" "$KERNELGIT" "$KERNELDIR"
    fi
fi

if step 22 "Building a Kernel - Configuration"; then
    (cd "$KERNELDIR" && {
            run_quiet armmake socfpga_defconfig
            # General setup  --->
            run_quiet ./scripts/config --enable CONFIG_FHANDLE
            # Enable the block layer  --->
            run_quiet ./scripts/config --enable CONFIG_LBDAF
            run_quiet ./scripts/config --enable CONFIG_BLK_DEV_BSG
            # File systems  --->
            run_quiet ./scripts/config --enable CONFIG_EXT2_FS_SECURITY
            run_quiet ./scripts/config --enable CONFIG_EXT3_FS_SECURITY
            run_quiet ./scripts/config --enable CONFIG_EXT4_FS_SECURITY
            run_quiet ./scripts/config --enable CONFIG_INOTIFY_USER

            if [[ $menuconfig == 1 ]]; then
                armmake menuconfig
            fi
        })
fi

if step 23 "Building a Kernel - Building"; then
    (cd "$KERNELDIR" && {
            yes "" | run_quiet make-kpkg --arch armhf --cross-compile "$KERNELCROSS" -j`numprocs` --revision 1 binary-indep binary-arch
        })
fi

if step 24 "Building a Kernel - Installing"; then
    (cd "$KERNELDIR" && {
            run_quiet armmake dtbs
        })
    mkdir -p "$MOUNTPOINT"
    run_quiet mount `partition "$dev" 1` "$MOUNTPOINT"
    run_quiet cp "$KERNELDIR/arch/arm/boot/zImage" "$MOUNTPOINT/zImage"
    run_quiet cp "$KERNELDIR/arch/arm/boot/dts/$KERNELDTB" "$MOUNTPOINT/socfpga.dtb"
    run_quiet umount "$MOUNTPOINT"
fi

if step 31 "Installing Debian - Base"; then
    mkdir -p "$MOUNTPOINT"
    run_quiet mount `partition "$dev" 2` "$MOUNTPOINT"
    run_quiet qemu-debootstrap --arch=armhf "$CODENAME" "$MOUNTPOINT" "$MIRROR"
    
    run_quiet cp linux-doc-`kerneldeb`_1_all.deb "$MOUNTPOINT/root/"
    run_quiet cp linux-manual-`kerneldeb`_1_all.deb "$MOUNTPOINT/root/"
    run_quiet cp linux-source-`kerneldeb`_1_all.deb "$MOUNTPOINT/root/"
    run_quiet cp linux-headers-`kerneldeb`_1_armhf.deb "$MOUNTPOINT/root/"
    run_quiet cp linux-image-`kerneldeb`_1_armhf.deb "$MOUNTPOINT/root/"
    run_quiet cp linux-image-`kerneldeb`-dbg_1_armhf.deb "$MOUNTPOINT/root/"
    
    run_quiet chroot "$MOUNTPOINT" dpkg -i /root/linux-image-`kerneldeb`_1_armhf.deb
    run_quiet chroot "$MOUNTPOINT" dpkg -i /root/linux-headers-`kerneldeb`_1_armhf.deb
    
    run_quiet umount "$MOUNTPOINT"
fi

if step 32 "Installing Debian - Setting Up Users"; then
    run_quiet mount `partition "$dev" 2` "$MOUNTPOINT"
    # 5 blank lines for blank (fullname, room#, workphone, homephone, other)
    run_quiet chroot "$MOUNTPOINT" adduser --add_extra_groups "$USERNAME" << EOF
$PASSWORD
$PASSWORD




Y
EOF
    run_quiet chroot "$MOUNTPOINT" adduser "$USERNAME" sudo
    run_quiet chroot "$MOUNTPOINT" passwd -l root
    run_quiet umount "$MOUNTPOINT"
fi

if step 33 "Installing Debian - Installing Tools"; then
    run_quiet mount `partition "$dev" 2` "$MOUNTPOINT"
    run_quiet chroot "$MOUNTPOINT" debconf-set-selections << EOF
locales locales/locales_to_be_generated multiselect     $LOCALE UTF-8
locales locales/default_environment_locale      select  $LOCALE
EOF

    yes | run_quiet chroot "$MOUNTPOINT" apt-get install locales ntp openssh-server sudo
    killall -qw "$MOUNTPOINT/usr/bin/qemu-arm-static"

    run_quiet sed -i 's/PermitRootLogin without-password/PermitRootLogin no/' "$MOUNTPOINT/etc/ssh/sshd_config"

    echo "$TIMEZONE" | run_quiet tee "$MOUNTPOINT/etc/timezone"
    run_quiet chroot "$MOUNTPOINT" dpkg-reconfigure -f noninteractive tzdata

    run_quiet umount "$MOUNTPOINT"
fi

if step 34 "Installing Debian - Setting up Networking"; then
    run_quiet mount `partition "$dev" 2` "$MOUNTPOINT"
    run_quiet tee -a "$MOUNTPOINT/etc/network/interfaces" << EOF
allow-hotplug eth0
iface eth0 inet dhcp
EOF
    run_quiet tee "$MOUNTPOINT/etc/hostname" << EOF
$HOSTNAME
EOF
    run_quiet tee "$MOUNTPOINT/etc/hosts" << EOF
127.0.0.1       localhost $HOSTNAME
::1             localhost ip6-localhost ip6-loopback $HOSTNAME
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters
EOF
    run_quiet umount "$MOUNTPOINT"
fi

if step 35 "Installing Debian - Fix APT Sources"; then
    run_quiet mount `partition "$dev" 2` "$MOUNTPOINT"
    run_quiet tee "$MOUNTPOINT/etc/apt/sources.list" << EOF
deb $MIRROR $CODENAME main contrib non-free
deb-src $MIRROR $CODENAME main contrib non-free
    
deb $SECMIRROR ${CODENAME}/updates main contrib non-free
deb-src $SECMIRROR ${CODENAME}/updates main contrib non-free
    
# ${CODENAME}-updates, previously known as 'volatile'
deb $MIRROR ${CODENAME}-updates main contrib non-free
deb-src $MIRROR ${CODENAME}-updates main contrib non-free
EOF
    run_quiet chroot "$MOUNTPOINT" apt-get update
    run_quiet umount "$MOUNTPOINT"
fi

echo ""
echo "Install successfull."
