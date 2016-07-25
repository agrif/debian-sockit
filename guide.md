Debian on Arrow SoCKit
======================

This guide will walk you through the process of creating a MicroSD
card suitable for booting a SoCKit board into Debian, from scratch
(insofar as that is possible).

[TOC]

If you just want to get started, it is probably easier to get a
pre-made Debian image from someone. This guide just notes how that
image is created, if none already exist.

This guide is loosely based off
[Exploring the Arrow SoCKit Part II][mao], by Howard Mao. The rest of
his tutorial is amazing, and worth a look.

 [mao]: https://zhehaomao.com/blog/fpga/2013/12/24/sockit-2.html

Preparing a Workspace
---------------------

This guide is written for use on an existing Debian Jessie
installation, with access to a Micro SD card reader. It might work in
other situations with some changes. I recommend using a VM.

It would be a good idea to run this whole guide inside a new, empty
directory, just for a clean work space.

You will need about 1.8GB of free space to work in. In addition, your
SD card needs to be 1GB or more. If you are working on Debian, the
tools you need to follow this guide will take up about 3GB more.

To complete the build, you'll need some tools installed:

 * *curl*: to fetch a codesigning key
 * *debootstrap*: to install the Debian root
 * *git*: to clone a copy of the Linux kernel sources
 * *kernel-package*: to build Debian kernel packages
 * *ncurses-dev*: to build the kernel's configuration menu
 * *qemu-user-static*: for *qemu-debootstrap*, to install the Debian root

On Debian, you can install all these with:

    $ sudo apt-get install curl debootstrap git kernel-package \
        ncurses-dev qemu-user-static

Additionally, you'll need a
[cross-compilation toolchain for ARM][cross]. To install those, create
the file */etc/apt/sources.list.d/crosstools.list* and add the
following:

 [cross]: http://emdebian.org/tools/debian/

    deb http://emdebian.org/tools/debian/ jessie main

You will also need to install the codesigning key they use:

    $ curl http://emdebian.org/tools/debian/emdebian-toolchain-archive.key \
        | sudo apt-key add -

Now, you can add *armhf* to your architecture list, update your
package list and install the toolchain:

    $ sudo dpkg --add-architecture armhf
    $ sudo apt-get update
    $ sudo apt-get install crossbuild-essential-armhf

Preparing the SD Card
---------------------

First, you will need to identify which device in */dev* represents
your SD card. One way to do this is to insert a new SD card, wait for
your desktop environment to automatically mount it, then run the
*mount* command to see what's new.

Be sure you get this right! If you accidentally try to run the
following commands on the wrong device, you could destroy data on your
hard drives.

If you don't have an SD card handy, or don't want to try this, you can
also create a disk image and set it up as a loopback device:

    $ dd if=/dev/zero of=my_debian_image.img bs=1M count=1024
    $ sudo losetup --show -fP my_debian_image.img

The last command will print a line (probably */dev/loop0*); this is
your device.

From now on, I will use */dev/sdcard* as my device name. Subtitute
your actual device name as needed.

### Partitioning

The SoCKit needs at least three partitions on the SD card to
boot. These are:

 * a bootloader, 1MiB, starting at sector 2048, with ID 0xA2
 * a boot information partition, FAT formatted, as partition #1
 * a root partition, as partition #2

Since partitions #1 and #2 are taken by boot and root, we will stick
the bootloader partition in slot #3.

Let's launch *fdisk* and make these partitions. First off, we need to
clear the existing table (if any):

    $ sudo fdisk /dev/sdcard
    Welcome to fdisk (util-linux 2.25.2).
    ...
    
    Command: o                               # create a new DOS partition table

Now, we need to make the bootloader partition (#3):

    Command: n                               # new partition (for bootloader)
    Select: p                                # primary
    Partition number: 3                      # third slot
    First sector: 2048                       # start at sector 2048
    Last sector, +sectors or +size: +2048    # make it 2048 sectors long
    
    Created a new partition 3 of type 'Linux' and of size 1 MiB.
    
    Command: t                               # change the type of our new partition
    Hex code: a2                             # 0xA2 is our special bootloader type
    Changed type of partition 'Linux' to 'unknown'.

Next up is the boot information partition (#1):

    Command: n                               # new partition (for boot info)
    Select: p                                # primary
    Partition number: 1                      # first slot
    First sector: <enter>                    # accept default for start
    Last sector, +sectors or +size: +128M    # give it 128MiB
    
    Created a new partition 1 of type 'Linux' and of size 128MiB.
    
    Command: t                               # change the type of our new partition
    Partition number: 1                      # that is, partition 1
    Hex code: 0b                             # mark it as W95 FAT32
    Changed type of partition 'Linux' to 'W95 FAT32'.

And finally the root partition (#2):

    Command: n                               # new partition (root)
    Select: p                                # primary
    Partition number: 2                      # second slot
    First sector: <enter>                    # accept default for start
    Last sector, +sectors or +size: <enter>  # accept default for end
    
    Created a new partition 2 of type 'Linux' and of size <...>.

In principle, you can do anything you want with the fourth (unused)
partition, and it won't affect the boot. We choose to ignore it, and
use all remaining free space for the root partition (#2).

Before we're done, you should print out the table you've constructed
and inspect it, then write it out to disk.
    
    Command: p                               # print it out, make sure it looks about right
    Command: w                               # write changes to disk (cannot be undone)

Once *fdisk* exits, you should have three shiny new partitions to format.

### Formatting

Our boot information partition (#1) needs a FAT filesystem:

    $ sudo mkfs.vfat -n "BOOT INFO" /dev/sdcard1

For our root partition (#2), we will use Ext4:

    $ sudo mkfs.ext4 -L "Debian Jessie" /dev/sdcard2

Our bootloader partition (#3) isn't a filesystem, it's a binary blob
containing [U-Boot][uboot], and a bit of code to interface it with the
SoCKit board. At the moment, I have [no idea][] how this blob is
created, but it should have been included alongside this guide as
*uboot.img*. We will write that to the disk now:

 [uboot]: http://www.denx.de/wiki/U-Boot
 [no idea]: https://rocketboards.org/foswiki/view/Documentation/GSRD151SDCardArrowSoCKitEdition

    $ sudo dd if=uboot.img of=/dev/sdcard3 bs=4k

Now that we have the SD card set up, we can start putting data on it.

Building a Kernel
-----------------

Our boot information filesystem needs to contain at least two files:

 * *zImage*, a compressed Linux kernel
 * *socfpga.dtb*, a [device tree][dtb] describing board layout
 
 [dtb]: http://elinux.org/Device_Tree

Both of these can be created from the Linux kernel source tree, which
we will clone from Altera via *git*. We'll use a shallow clone and
only check out the specific tag we need, as the Linux git repository
is gigantic.

    $ git clone --depth=1 -b ACDS13.1_REL_GSRD_PR \
            https://github.com/altera-opensource/linux-socfpga.git

This tag is known to work, but a bit old. It might be worth trying newer tags.

Before we continue, we'll set up a quick *bash* alias to make
cross-building for ARM easier:

    $ alias armmake='make CROSS_COMPILE=arm-linux-gnueabihf- ARCH=arm'

Ok. Move into the shiny new kernel sources, and set up the default
configuration for the SoCKit:

    $ cd linux-socfpga
    $ armmake socfpga_defconfig

This is a good start, but there are a few kernel options we need to
enable to get Debian Jessie running:

    $ armmake menuconfig

You should now have a configuration menu. Navigate to, and enable, the
following options. Now would be a great time to enable any other
kernel stuff you want.

    General setup  --->
        [*] open by fhandle syscalls
    Enable the block layer  --->
        [*] Support for large (2TB+) block devices and files
        [*] Block layer SG support v4
    File systems  --->
        [*] Inotify support for userspace
        [*]     Ext3 Security Labels
        [*]   Ext4 Security Labels

Exit the menu, and be sure to save! Now we are going to use
[*make-kpkg*][kpkg] to build a Debian kernel package from these
sources, and along the way, our *zImage*. This can take a *long time*,
so we will build in parallel: change the *2* in `-j2` to the number of
CPUs on your build machine.

 [kpkg]: http://man.he.net/man1/make-kpkg

    $ fakeroot make-kpkg --arch armhf --cross-compile arm-linux-gnueabihf- \
        -j2 --revision 1 binary-indep binary-arch

This stuck a bunch of Debian packages in the directory above your
kernel source. We'll use those later. Now we just need the device
trees:

    $ armmake dtbs

Move back outside the kernel source, and mount our boot information
partition (#1) somewhere temporary:

    $ cd ..
    $ mkdir mnt
    $ sudo mount /dev/sdcard1 mnt/

Now we copy the two files we need into place:

    $ sudo cp linux-socfpga/arch/arm/boot/zImage mnt/zImage
    $ sudo cp linux-socfpga/arch/arm/boot/dts/socfpga_cyclone5.dtb \
        mnt/socfpga.dtb

There are a few other things you can add to this partition, in
particular a *[u-boot.scr][]* file, which U-Boot reads and executes at
boot. This can be used to customize the boot process, but it's not
required, so we skip it here.

 [u-boot.scr]: https://lists.rocketboards.org/pipermail/rfi/2014-April/001602.html

Unmount the boot information partition:

    $ sudo umount mnt/

Your boot information partition is now finished.

Installing Debian
-----------------

We will be using the *qemu-debootstrap* tool to install Debian on to
the root partition. First, though, we have to mount the root partition
(#2):

    $ sudo mount /dev/sdcard2 mnt/

We'll be installing Debian Jessie from the official mirror, but other
mirrors and releases will likely work:

    $ sudo qemu-debootstrap --arch=armhf jessie mnt/ http://ftp.debian.org/debian/

Lastly, we'll install the Debian kernel packages we made earlier. All
we need right now are the kernel modules and headers, but we copy the
others into */root* in case we need them later.

    $ sudo cp *.deb mnt/root/
    $ sudo chroot mnt/ dpkg -i /root/linux-image-3.9.0-ged01b8c_1_armhf.deb
    $ sudo chroot mnt/ dpkg -i /root/linux-headers-3.9.0-ged01b8c_1_armhf.deb

(Exact file names may differ depending on kernel version.)

As of now, you have a fully functioning Debian system, but there are a
handful of niceties to finish up.

### Setting Up Users

Running things as *root* all the time is (generally speaking) a bad
idea. To create a new user for everyday work:

    $ sudo chroot mnt/ adduser --add_extra_groups <username>

To give this user access to *sudo* so they can become root:

    $ sudo chroot mnt/ adduser <username> sudo

Since we have this user, we'll lock root logins:

    $ sudo chroot mnt/ passwd -l root

### Installing Tools

There are a couple of Debian packages you would probably like to have:

 * *locales*: mostly to get rid of errors, but also to handle locales
 * *ntp*: to set the correct time on boot via the Internet
 * *openssh-server*: for remote shell access
 * *sudo*: to get root access

To install these:

    $ sudo chroot mnt/ apt-get install locales ntp openssh-server sudo

By default, the SSH server allows logging in remotely as root. This is
a pretty bad idea, so edit *mnt/etc/ssh/sshd_config* and change the
following line:

    PermitRootLogin without-password
    # change to:
    PermitRootLogin no

If you care to, you can change the default timezone from UTC to
something more appropriate:

    $ sudo chroot mnt/ dpkg-reconfigure tzdata

Finally, reconfigure locales to use the *en_US.UTF-8* locale:

    $ sudo chroot mnt/ dpkg-reconfigure locales

These commands have started a few services accidentally. You can kill
them with:

    $ sudo killall mnt/usr/bin/qemu-arm-static

### Setting up Networking

To have the ethernet device automatically set itself up with DHCP on
boot (which is usually what you want), edit the file
*mnt/etc/network/interfaces* and add the following lines:

    allow-hotplug eth0
    iface eth0 inet dhcp

By default, the new Debian install will have the same hostname as the
host you built it on. This can be confusing. Edit *mnt/etc/hostname*
to change it, then edit *mnt/etc/hosts* to add the new hostname:

    127.0.0.1       localhost <hostname>
    ::1             localhost ip6-localhost ip6-loopback <hostname>
    ff02::1         ip6-allnodes
    ff02::2         ip6-allrouters

### Fix APT Sources

Debootstrap installs a very minimal list of sources for APT to use. To
fix it, open *mnt/etc/apt/sources.list* and replace the whole thing
with:

    deb http://ftp.us.debian.org/debian jessie main contrib non-free
    deb-src http://ftp.us.debian.org/debian jessie main contrib non-free
    
    deb http://security.debian.org/ jessie/updates main contrib non-free
    deb-src http://security.debian.org/ jessie/updates main contrib non-free
    
    # jessie-updates, previously known as 'volatile'
    deb http://ftp.us.debian.org/debian jessie-updates main contrib non-free
    deb-src http://ftp.us.debian.org/debian jessie-updates main contrib non-free

Make sure these new mirrors work by updating your package list:

    $ sudo chroot mnt/ apt-get update

Finishing Up
------------

Now that everything's in place, we can unmount the root partition:

    $ sudo umount mnt/

If you are writing to a disk image over a loopback device, now is the
time to destroy that, too:

    $ sudo losetup -d /dev/sdcard

Your SD card is finished! Go and boot it, and watch over the USB
serial console. When the time comes, you will be able to log in with
username and password you set earlier.

If you created the card using an image, now would be an excellent time
to expand the root partition to cover the rest of the card, and resize
the root filesystem.
