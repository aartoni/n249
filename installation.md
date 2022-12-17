# Installation

This guide will help installing the [InkBox](https://inkbox.ddns.net/) open-source operating system on the Kobo Clara HD (N249).

## Compiling the bootloader and kernel

Start by creating a new home directory for the build process and cloning the InkBox repository in it.

```sh
sudo mkdir -p /home/build/inkbox
sudo chown -R "$USER:$(id -gn)" /home/build
cd /home/build/inkbox && git clone git@github.com:Kobo-InkBox/kernel.git
```

> Note: the `/home/build/inkbox` path is hardcoded in the make process, avoid changing it.

```sh
cd /home/build/inkbox/kernel
env TOOLCHAINDIR=/home/build/inkbox/kernel/toolchain/arm-kobo-linux-gnueabihf TARGET=arm-kobo-linux-gnueabihf THREADS=$(($(nproc)*2)) scripts/build_u-boot.sh n249
```

You should see the built bootloader in `bootloader/out/u-boot_inkbox.n249.imx`. Now, let's build the kernel.

```sh
env GITDIR=/home/build/inkbox/kernel TOOLCHAINDIR=/home/build/inkbox/kernel/toolchain/armv7l-linux-musleabihf-cross/ THREADS=$(($(nproc)*2)) TARGET=armv7l-linux-musleabihf scripts/build_kernel.sh n249 root
```

You should see the built kernel in `kernel/out/n249/zImage-root`.

## Build the rootfs

Get the rootfs, but clone it as root to avoid permissions problems later on the Kobo, then build it.

```sh
sudo git clone git@github.com:Kobo-InkBox/rootfs.git
cd rootfs
env GITDIR="${PWD}" ./release.sh
```

Create your RSA keys.

```sh
openssl genrsa -out private.pem 2048
openssl rsa -in private.pem -out public.pem -outform PEM -pubout
```

Finally sign the rootfs.

```sh
openssl dgst -sha256 -sign private.pem -out rootfs.squashfs.dgst rootfs.squashfs
```
