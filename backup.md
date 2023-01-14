# Backup and restore

## Remove the microSD

Remove the back cover of the e-reader and follow the [safety measures](safety.md) if you haven't yet. Then carefully remove the microSD card and connect it to your computer.

## Backup

Now backup all the partitions at once using `dd`.

```sh
dd if=/dev/<microsd> bs=4M conv=sync,noerror | xz > kobo-backup.img.xz
```

> Note: you can find the block size (`bs`) of the device by running `stat -fc %s /dev/<microsd>`

> Note: `conv=sync,noerror` tells `dd` that if it can't read a block due to a read error, then it should at least write something to its output of the correct length<sup>[1](https://www.inference.org.uk/saw27/notes/backup-hard-disk-partitions.html)</sup>

## Restore

To restore the backup, simply uncompress the image and write it to the microSD.

```sh
xz -dc kobo-backup.img.xz | sudo dd of=/dev/<microsd> bs=4M status=progress
```
