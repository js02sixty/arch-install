#!/bin/bash

##
# use:
# dd if=/dev/zero of=/dev/sda bs=512 count=1 conv=notrunc
# to clean partition
##
ml=/etc/pacman.d/mirrorlist
mv $ml $ml.bak
curl -o $ml "https://www.archlinux.org/mirrorlist/?country=US&protocol=http&ip_version=4"
sed -i 's/^#\(.*\)/\1/g' $ml

timedatectl set-ntp true

parted --script /dev/sda mklabel gpt
parted --script /dev/sda mkpart ESP fat32 1MiB 513MiB
parted --script /dev/sda set 1 boot on
parted --script /dev/sda mkpart primary ext4 513MiB 100%
parted --script /dev/sda set 2 lvm on

pvcreate /dev/sda2
vgcreate vg_os /dev/sda2
lvcreate vg_os -n lv_swap -L 4G
lvcreate vg_os -n lv_root -l 100%FREE
#lvcreate vg_os -n lv_home -l 100%FREE

mkswap /dev/vg_os/lv_swap
swapon /dev/vg_os/lv_swap

mkfs.vfat -F32 /dev/sda1
mkfs.ext4 /dev/vg_os/lv_root
#mkfs.ext4 /dev/vg_os/lv_home
mkfs.xfs /dev/sdb

mount /dev/vg_os/lv_root /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
mkdir -p /mnt/home
#mount /dev/vg_os/lv_home /mnt/home
mount /dev/sdb /mnt/home

pacstrap -i /mnt base base-devel

genfstab -U /mnt > /mnt/etc/fstab
echo en_US.UTF-8 UTF-8 >> /mnt/etc/locale.gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
sed '/^HOOKS/s/block/block lvm2/' -i /mnt/etc/mkinitcpio.conf

##arch-chroot /mnt /bin/bash
arch-chroot /mnt locale-gen
arch-chroot /mnt ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
arch-chroot /mnt hwclock --systohc --utc
arch-chroot /mnt mkinitcpio -p linux
arch-chroot /mnt pacman -S --noconfirm dosfstools networkmanager \
vim xorg-server xorg-xinit xorg virtualbox-guest-modules virtualbox-guest-utils \
zsh openssh firefox gnome gnome-tweak-tool
arch-chroot /mnt bootctl --path=/boot install

bentry=/mnt/boot/loader/entries/arch.conf
echo "title          Arch Linux" >> $bentry
echo "linux          /vmlinuz-linux" >> $bentry
echo "initrd         /initramfs-linux.img" >> $bentry
echo "options        root=/dev/vg_os/lv_root rw" >> $bentry

ldrcfg=/mnt/boot/loader/loader.conf
echo "timeout 2" >> $ldrcfg
echo "default arch">> $ldrcfg

#-servarch-chroot /mnt timedatectl set-ntp true
arch-chroot /mnt timedatectl set-timezone America/New_York
arch-chroot /mnt systemctl enable NetworkManager gdm vboxservice

#reboot
