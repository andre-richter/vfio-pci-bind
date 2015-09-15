#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# =============================================================================
#
# The MIT License (MIT)
#
# Copyright (c) 2015 Andre Richter
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# =============================================================================
#
# Author(s):
#   Andre Richter, <andre.o.richter @t gmail_com>
#
# =============================================================================
#
# This script takes a Domain:Bus:Device.Function string of the form
# "0000:00:00.0" as command line argument and:
#
#  (1) Unbinds all devices that are in the same iommu group as the supplied
#      device from their current driver (except PCIe bridges).
#
#  (2) Binds to vfio-pci:
#    (2.1) The supplied device.
#    (2.2) All devices that are in the same iommu group.
#
#  (3) Transfers ownership of the respective iommu group inside /dev/vfio
#      to $SUDO_USER
#
# Script must be executed via sudo

BDF_REGEX="^[[:xdigit:]]{2}:[[:xdigit:]]{2}.[[:xdigit:]]$"
DBDF_REGEX="^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}.[[:xdigit:]]$"

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

if [[ $1 =~ $DBDF_REGEX ]]; then
    BDF=$1
elif [[ $1 =~ $BDF_REGEX ]]; then
    BDF="0000:$1"
    echo "Warning: You did not supply a PCI domain, assuming $BDF" 1>&2
else
    echo "Please supply Domain:Bus:Device.Function of PCI device in form: dddd:bb:dd.f" 1>&2
    exit 1
fi

TARGET_DEV_SYSFS_PATH="/sys/bus/pci/devices/$BDF"

if [[ ! -d $TARGET_DEV_SYSFS_PATH ]]; then
    echo "There is no such device"
    exit 1
fi

if [[ ! -d "$TARGET_DEV_SYSFS_PATH/iommu/" ]]; then
    echo "No signs of an IOMMU. Check your hardware and/or linux cmdline parameters." 1>&2
    echo "Use intel_iommu=on or iommu=pt iommu=1" 1>&2
    exit 1
fi

for dsp in $TARGET_DEV_SYSFS_PATH/iommu_group/devices/*
do
    dbdf=${dsp##*/}
    if [[ $(( 0x$(setpci -s $dbdf 0e.b) & 0x7f )) -eq 0 ]]; then
	dev_sysfs_paths+=( $dsp )
    fi
done

printf "\nIOMMU group members (sans bridges):\n"
for dsp in ${dev_sysfs_paths[@]}; do echo $dsp; done

modprobe -i vfio-pci
if [[ $? -ne 0 ]]; then
    echo "Error probing vfio-pci"
    exit 1
fi

printf "\nBinding...\n"
for dsp in ${dev_sysfs_paths[@]}
do
    dpath="$dsp/driver"
    dbdf=${dsp##*/}

    echo "vfio-pci" > "$dsp/driver_override"

    if [[ -d $dpath ]]; then
	curr_driver=$(readlink $dpath)
	curr_driver=${curr_driver##*/}

	if [[ $curr_driver -ne "vfio-pci" ]]; then
	    echo "$dbdf already bound to vfio-pci"
	    continue
	else
	    echo $dbdf > "$dpath/unbind"
	    echo "Unbound $dbdf from $curr_driver"
	fi
    fi

    echo $dbdf > /sys/bus/pci/drivers_probe
done

printf "\n"

# Adjust group ownership
iommu_group=$(readlink $TARGET_DEV_SYSFS_PATH/iommu_group)
iommu_group=${iommu_group##*/}
chown $SUDO_UID:$SUDO_GID "/dev/vfio/$iommu_group"
if [[ $? -ne 0 ]]; then
    echo "Error adjusting group ownership"
    exit 1
fi

printf "success...\n\n"
echo 'Devices listed in /sys/bus/pci/drivers/vfio-pci:'
ls -l /sys/bus/pci/drivers/vfio-pci | egrep [[:xdigit:]]{4}:
printf "\nls -l /dev/vfio/\n"
ls -l /dev/vfio/
