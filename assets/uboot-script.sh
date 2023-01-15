led tolinoshine2hd:white:on on
setenv bootargs console=ttymxc0,115200

echo Loading kernel
load mmc 0:1 0x80800000 zImage

echo Loading DTB
load mmc 0:1 0x83000000 DTB

echo Booting kernel
bootz 0x80800000 - 0x83000000
