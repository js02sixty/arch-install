#!/bin/bash

## Personalization
echo "Enter username"
read newuser
echo "Enter password"
read newpw
echo "Enter root password"
read rpw
echo "Enter hostname"
read hname

## Adjust Time
timedatectl set-ntp true
## Update Mirrorlist Sources
ml=/etc/pacman.d/mirrorlist
mv $ml $ml.bak
curl -o $ml "https://www.archlinux.org/mirrorlist/?country=US&protocol=http&ip_version=4"
sed -i 's/^#\(.*\)/\1/g' $ml

## Remove old paritions
#for lvol in $(lvs|awk 'NR > 1 {print $1}')
#do
#    lvremove ${lvol} --force
#done
lvremove $(vgs | awk 'NR==2 {print $1}') --force
vgremove $(vgs | awk 'NR==2 {print $1}') --force
pvremove $(pvs | awk 'NR==2 {print $1}') --force

for part in $(parted -s /dev/sda print|awk '/^ / {print $1}')
do
    parted -s /dev/sda rm ${part}
done

## Partition Drive
parted --script /dev/sda mklabel gpt
parted --script /dev/sda mkpart ESP fat32 1MiB 513MiB
parted --script /dev/sda set 1 boot on
parted --script /dev/sda mkpart primary ext4 513MiB 100%
parted --script /dev/sda set 2 lvm on

pvcreate /dev/sda2
vgcreate vg_os /dev/sda2
lvcreate vg_os -n lv_swap -L 4G --yes
lvcreate vg_os -n lv_root -L 60G --yes
lvcreate vg_os -n lv_home -l 100%FREE --yes

mkswap /dev/vg_os/lv_swap
swapon /dev/vg_os/lv_swap

mkfs.vfat -F32 /dev/sda1
mkfs.ext4 /dev/vg_os/lv_root
mkfs.ext4 /dev/vg_os/lv_home

mount /dev/vg_os/lv_root /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
mkdir -p /mnt/home
mount /dev/vg_os/lv_home /mnt/home

## Install Distro
pacstrap /mnt \
	base \
	base-devel \
	grub efibootmgr dosfstools \
	networkmanager \
	firewalld \
	zsh \
	vim git \
	openssh \
	gnome gnome-extra \
	firefox
	
## Set Time
arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
arch-chroot /mnt hwclock --systohc --utc

## Set Locale
echo en_US.UTF-8 UTF-8 >> /mnt/etc/locale.gen
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
arch-chroot /mnt locale-gen

## Configure OS
genfstab -U /mnt >> /mnt/etc/fstab
sed '/^HOOKS/s/block/block lvm2/' -i /mnt/etc/mkinitcpio.conf
echo $hname > /mnt/etc/hostname
arch-chroot /mnt mkinitcpio -p linux

# virtualbox-guest-modules
# virtualbox-guest-utils

## Enable Services
arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt systemctl enable gdm
arch-chroot /mnt systemctl enable firewalld
arch-chroot /mnt systemctl enable sshd

## Set Permissions
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh $newuser
arch-chroot /mnt echo $newuser:$newpw | chpasswd
arch-chroot /mnt echo root:$rpw | chpasswd
sed '/^# %wheel ALL=(ALL) NOPASSWD: ALL/ s/^#//' -i /mnt/etc/sudoers

## Boot Loader
sed 's/GRUB_TIMEOUT=5/GRUB_TIMEOUT=2/' -i /mnt/etc/default
sed 's/part_msdos/part_msdos lvm/' -i /mnt/etc/default
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

reboot
