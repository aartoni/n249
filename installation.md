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

## Sign overlaymount-rootfs

InkBox has a reproducible image builder. Download it and sign the `overlaymount-rootfs.squashfs` file using your private key.

```sh
git clone git@github.com:Kobo-InkBox/imgtool.git
openssl dgst -sha256 -sign private.pem -out imgtool/sd/overlaymount-rootfs.squashfs.dgst imgtool/sd/overlaymount-rootfs.squashfs
```

## Create the `boot.scr` file

Create the `boot.scr` to automate the execution of the [`uboot-script.sh`](assets/uboot-script.sh) script.

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

Launch `sudo fdisk /dev/<microsd>`, clear the partition table with `o`, look up the partitions with `p`, and create new ones with `n`. Now create new partition until you obtain the exact same structure as below.

    Device          Boot   Start     End Sectors  Size Id Type
    /dev/<microsd>1        49152   79871   30720   15M 83 Linux
    /dev/<microsd>2       104448 1128447 1024000  500M 83 Linux
    /dev/<microsd>3      1128448 1390591  262144  128M 83 Linux
    /dev/<microsd>4      1390592 8388607 6998016  3.3G 83 Linux

> Note: the last partition can be extended to the end of the microSD card

Format the four partitions in ext4.

```sh
mkfs.ext4 -O "^metadata_csum" /dev/<microsd>${partition}
```

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

Unmount the microSD from your computer, put it inside the e-reader, establish a [serial connection](serial.md) and boot the device. Once in the U-Boot shell set the boot script and reboot.

    setenv bootcmd load mmc 0:1 ${loadaddr} /boot.scr \; source ${loadaddr}
    saveenv
    reset
