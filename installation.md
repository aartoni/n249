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
