#!/bin/sh

# format volume /dev/sda1 and mount to /dbt2-data
mkfs -t xfs /dev/sda1
mkdir /dbt2-data
mount /dev/sda1 /dbt2-data
cp /etc/fstab /etc/fstab.orig
echo -e "UUID=`sudo blkid /dev/sda1 -s UUID -o value`\t/dbt2-data\txfs\tdefaults,nofail  0  2" >> /etc/fstab

# Use this to install software packages
