# Installation

This guide will help installing the [InkBox](https://inkbox.ddns.net/) open-source operating system on the Kobo Clara HD (N249).

* 1 [Compiling the bootloader](#compiling-the-bootloader)
* 2 [Building the rootfs](#building-the-rootfs)
* 3 [Building the kernel](#building-the-kernel)
    * 3.1 [Putting the public key in place](#putting-the-public-key-in-place)
    * 3.2 [Compiling the initial ramdisk](#compiling-the-initial-ramdisk)
    * 3.3 [Compiling the kernel](#compiling-the-kernel)
* 4 [Signing overlaymount-rootfs](#signing-overlaymount-rootfs)
* 5 [Creating the boot script image](#creating-the-boot-script-image)
* 6 [Installing InkBox](#installing-inkbox)
    * 6.1 [Installing the bootloader](#installing-the-bootloader)
    * 6.2 [Formatting the microSD](#formatting-the-microsd)
    * 6.3 [Copying the needed files](#copying-the-needed-files)
* 7 [Post-install](#post-install)

## Compiling the bootloader

Start by creating a new home directory for the build process and cloning the InkBox repository in it.

```sh
sudo mkdir -p /home/build/inkbox/kernel
sudo chown -R "$USER:$(id -gn)" /home/build
git clone git@github.com:Kobo-InkBox/kernel.git /home/build/inkbox/kernel
```

> Note: the `/home/build/inkbox` path is hardcoded in the make process, avoid changing it.

```sh
cd /home/build/inkbox/kernel
env TOOLCHAINDIR=$PWD/toolchain/arm-kobo-linux-gnueabihf TARGET=arm-kobo-linux-gnueabihf THREADS=$(($(nproc)*2)) scripts/build_u-boot.sh n249
```

You should see the built bootloader in `bootloader/out/u-boot_inkbox.n249.imx`.

## Building the rootfs

Get the rootfs, but clone it as root to avoid permissions problems later on the Kobo, then build it.

```sh
cd /home/build/inkbox
sudo git clone https://github.com/Kobo-InkBox/rootfs
cd rootfs
sudo env GITDIR=$PWD ./release.sh
```

Create your RSA key pair and sign the rootfs with your private key.

```sh
cd /home/build/inkbox
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

### Compiling the initial ramdisk

Before compiling the kernel, a specific `initrd` is needed. Let's clone it and compile it.

```sh
git clone git@github.com:Kobo-InkBox/inkbox-os-init.git /home/build/inkbox/os-init
cd /home/build/inkbox/os-init
/home/build/inkbox/kernel/toolchain/armv7l-linux-musleabihf-cross/bin/armv7l-linux-musleabihf-gcc init.c -o init -static -D_GNU_SOURCE
/home/build/inkbox/kernel/toolchain/armv7l-linux-musleabihf-cross/bin/armv7l-linux-musleabihf-strip init
```

Then we'll overwrite the original `init` file with the compilation output.

```sh
cp /home/build/inkbox/os-init/init /home/build/inkbox/kernel/initrd/common/init
```

### Compiling the kernel

To compile the kernel, just move to the kernel directory and run the build script as follows.

```sh
cd /home/build/inkbox/kernel
env GITDIR=$PWD TOOLCHAINDIR=$PWD/toolchain/armv7l-linux-musleabihf-cross/ THREADS=$(($(nproc)*2)) TARGET=armv7l-linux-musleabihf scripts/build_kernel.sh n249 root
```

You should see the built kernel in `kernel/out/n249/zImage-root`.

## Signing overlaymount-rootfs

InkBox has a reproducible image builder. Download it and sign the `overlaymount-rootfs.squashfs` file using your private key.

```sh
cd /home/build/inkbox
git clone git@github.com:Kobo-InkBox/imgtool.git
openssl dgst -sha256 -sign private.pem -out imgtool/sd/overlaymount-rootfs.squashfs.dgst imgtool/sd/overlaymount-rootfs.squashfs
```

## Creating the boot script image

Create the `boot.scr` U-Boot image to automate the execution of the [`uboot-script.sh`](assets/uboot-script.sh) script.

```sh
mkimage -A arm -O linux -T script -n postmarketOS -d uboot-script.sh boot.scr
```

## Installing InkBox

Perform a [backup](backup.md), we will start from the bootloader.

### Installing the bootloader

Write the bootloader on the whole device.

```sh
dd if=bootloader/out/u-boot_inkbox.n249.imx of=/dev/<microsd> bs=1K seek=1
```

Create an environment [`u-boot-env.txt`](assets/u-boot-env.txt) for the bootloader.

```sh
mkenvimage -p 0 -s 8192 -o u-boot-env.bin u-boot-env.txt
dd if=u-boot-env.bin of=/dev/<microsd> bs=4096 seek=192
```

### Formatting the microSD

Run the [partition script](assets/partition-script.txt) as follows.

```sh
sudo sfdisk /dev/<microsd> < partition-script.txt
```

You can check the partition table by running `sudo fdisk -l /dev/<microsd>`, it should have the same structure as below.

    Device          Boot   Start     End Sectors  Size Id Type
    /dev/<microsd>1        49152   79871   30720   15M 83 Linux
    /dev/<microsd>2       104448 1128447 1024000  500M 83 Linux
    /dev/<microsd>3      1128448 1390591  262144  128M 83 Linux
    /dev/<microsd>4      1390592 8388607 6998016  3.3G 83 Linux

> Note: the last partition may be larger or smaller depending on the microSD card size.

Format the four partitions in ext4.

```sh
for partition in 1 2 3 4; do sudo mkfs.ext4 /dev/<microsd>${partition}; done
```

### Copying the needed files

Mount the third partition and copy the signed rootfs and overlaymount-rootfs to it.

```sh
mount /dev/<microsd>3 /mnt
cp rootfs.squashfs* /mnt
cp imgtool/sd/overlaymount-rootfs.squashfs* /mnt
```

Unmount the third partition, mount the second partition and copy the overlaymount-rootfs to it.

```sh
mount /dev/<microsd>2 /mnt
cp imgtool/sd/overlaymount-rootfs.squashfs* /mnt
```

Unmount the second partition, mount the first partition and copy the DTB, the zImage and the boot script to it.

```sh
mount /dev/<microsd>1 /mnt
cp kernel/kernel/out/n249/zImage-root /mnt
cp kernel/kernel/linux-5.16-n249/arch/arm/boot/dts/imx6sll-kobo-clarahd.dtb /mnt
cp boot.scr /mnt
```

Write the Root kernel flag to a specific sector of the microSD card, which will allow us to interface with the device via USBNet, SSH, etc. and have root access.

```sh
printf "rooted\n" | sudo dd of=/dev/<microsd> bs=512 seek=79872
```

## Post-install

Unmount the microSD from your computer, put it inside the e-reader, establish a [serial connection](serial.md) and boot the device.
