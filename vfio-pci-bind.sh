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
# This script takes two parameters:
#   <Domain:Bus:Device.Function> (required) i.e. 0000:00:00.0
#   <Vendor:Device> (optional) i.e. 0000:0000
# and then:
#
#  (1) Verifies that the optional <Vendor:Device> matches the Vendor:Device 
#      currently at the requested <Domain:Bus:Device.Function> PCI address. 
#      If they do not match, exit without binding the requested PCI address. 
#      The goal is to prevent the wrong device from being bound to vfio-pci 
#      after a hardware change.
#
#  (2) Unbinds all devices that are in the same iommu group as the supplied
#      device from their current driver (except PCIe bridges).
#
#  (3) Binds to vfio-pci:
#    (3.1) The supplied device.
#    (3.2) All devices that are in the same iommu group.
#
#  (4) Transfers ownership of the respective iommu group inside /dev/vfio
#      to $SUDO_USER
#
# Script must be executed via sudo

BDF_REGEX="^[[:xdigit:]]{2}:[[:xdigit:]]{2}.[[:xdigit:]]$"
DBDF_REGEX="^[[:xdigit:]]{4}:[[:xdigit:]]{2}:[[:xdigit:]]{2}.[[:xdigit:]]$"
VD_REGEX="^[[:xdigit:]]{4}:[[:xdigit:]]{4}$"

if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root" 1>&2
    exit 1
fi

if [[ $1 =~ $DBDF_REGEX ]]; then
    BDF=$1
elif [[ $1 =~ $BDF_REGEX ]]; then
    BDF="0000:$1"
    echo "Warning: You did not supply a PCI domain, assuming $BDF" 1>&2
else
    echo "Error: Please supply Domain:Bus:Device.Function of PCI device in form: dddd:bb:dd.f" 1>&2
    exit 1
fi

TARGET_DEV_SYSFS_PATH="/sys/bus/pci/devices/$BDF"

if [[ ! -d $TARGET_DEV_SYSFS_PATH ]]; then
    echo "Error: Device ${BDF} does not exist, unable to bind device" 1>&2
    exit 1
fi

if [[ ! -d "$TARGET_DEV_SYSFS_PATH/iommu/" ]]; then
    echo "Error: No signs of an IOMMU. Check your hardware and/or linux cmdline parameters. Use intel_iommu=on or iommu=pt iommu=1" 1>&2
    exit 1
fi

if [[ $2 =~ $VD_REGEX ]]; then
    if [[ $(lspci -n -s ${BDF} -d $2 2>/dev/null | wc -l) -eq 0 ]]; then
        echo "Error: Vendor:Device $2 not found at ${BDF}, unable to bind device" 1>&2
        exit 1
    else
        echo "Vendor:Device $2 found at ${BDF}"
    fi
else
    echo "Warning: You did not specify a Vendor:Device in form vvvv:dddd, unable to validate ${BDF}" 1>&2
fi

unset dev_sysfs_paths
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
    echo "Error: Error probing vfio-pci" 1>&2
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

        if [[ "$curr_driver" == "vfio-pci" ]]; then
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
    echo "Error: unable to adjust group ownership of /dev/vfio/${iommu_group}" 1>&2
    exit 1
fi

printf "success...\n\n"
echo "Device $2 at ${BDF} bound to vfio-pci"
echo 'Devices listed in /sys/bus/pci/drivers/vfio-pci:'
ls -l /sys/bus/pci/drivers/vfio-pci | egrep [[:xdigit:]]{4}:
printf "\nls -l /dev/vfio/\n"
ls -l /dev/vfio/
