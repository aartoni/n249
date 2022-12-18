# Installation

This guide will help installing the [InkBox](https://inkbox.ddns.net/) open-source operating system on the Kobo Clara HD (N249).

## Compiling the bootloader

Start by creating a new home directory for the build process and cloning the InkBox repository in it.

```sh
sudo mkdir -p /home/build/inkbox
sudo chown -R "$USER:$(id -gn)" /home/build
cd /home/build/inkbox && git clone git@github.com:Kobo-InkBox/kernel.git
```

> Note: the `/home/build/inkbox` path is hardcoded in the make process, avoid changing it.

```sh
cd /home/build/inkbox/kernel
env TOOLCHAINDIR=$PWD/toolchain/arm-kobo-linux-gnueabihf TARGET=arm-kobo-linux-gnueabihf THREADS=$(($(nproc)*2)) scripts/build_u-boot.sh n249
```

You should see the built bootloader in `bootloader/out/u-boot_inkbox.n249.imx`.

## Build the rootfs

Get the rootfs, but clone it as root to avoid permissions problems later on the Kobo, then build it.

```sh
cd /home/build/inkbox
sudo git clone https://github.com/Kobo-InkBox/rootfs
cd rootfs
sudo env GITDIR=$PWD ./release.sh
```

Create your RSA key pair and sign the rootfs with your private key.

```sh
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -out public.pem -outform PEM -pubout
openssl dgst -sha256 -sign private.pem -out rootfs.squashfs.dgst rootfs.squashfs
```

## Building the kernel

First, we need to put our public RSA key in a trusted kernel space, then compile the kernel image.

### Putting the public key in place

The key is located inside a squashfs, we need to unsquash it, update the key and put it back in place.

```sh
cd /home/build/inkbox
sudo unsquashfs kernel/initrd/n249/opt/key.sqsh
cp public.pem squashfs_root
mksquashfs squashfs-root kernel/initrd/n249/opt/key.sqsh -noappend
```

> Note: unsquashing with `sudo` is required to preserve x-attrs.

> Note: don't `mv` your `public.pem` file to the unsquashed directory, otherwise file ownership will be ovewritten.

You can now check if the squashfs contains your `public.pem` by mounting it.

```sh
sudo mount -t squashfs kernel/initrd/n249/opt/key.sqsh /mnt
```

### Compiling the kernel

To compile the kernel, just move to the kernel directory and run the build script as follows.

```sh
cd /home/build/inkbox/kernel
env GITDIR=$PWD TOOLCHAINDIR=$PWD/toolchain/armv7l-linux-musleabihf-cross/ THREADS=$(($(nproc)*2)) TARGET=armv7l-linux-musleabihf scripts/build_kernel.sh n249 root
```

You should see the built kernel in `kernel/out/n249/zImage-root`.

## Installing InkBox

Perform a [backup](backup.md), we will start from the bootloader.

### Installing the bootloader

Write the bootloader on the whole device.

```sh
dd if=bootloader/out/u-boot_inkbox.n249.imx of=/dev/<microsd> bs=1K seek=1
```

Setup a [serial connection](serial.md), then connect the e-reader to a computer with the USB cable and execute `ums 0 mmc 0` in the U-Boot shell.

Launch `sudo fdisk /dev/<sdcard>`, clear the partition table with `o`, look up the partitions with `p`, and create new ones with `n`. Now create new partition until you obtain the exact same structure as below.

    Device      Boot   Start     End Sectors  Size Id Type
    /dev/nbd0p1        49152   79871   30720   15M 83 Linux
    /dev/nbd0p2       104448 1128447 1024000  500M 83 Linux
    /dev/nbd0p3      1128448 1390591  262144  128M 83 Linux
    /dev/nbd0p4      1390592 8388607 6998016  3.3G 83 Linux

> Note: the last partition can be extended to the end of the microSD card

Format the four partitions in ext4.

```sh
mkfs.ext4 -O "^metadata_csum" /dev/<sdcard>p${partition}
```

Finally, write the Root kernel flag to a specific sector of the microSD card, which will allow us to interface with the device via USBNet, SSH, etc. and have root access.

```sh
printf "rooted\n" | dd of=/dev/sdcard bs=512 seek=79872
```
