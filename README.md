# pci-bind-vfio

This script takes a Bus:Device:Function string of the form "00:00.0"
as command line argument and:

1. Unbinds all devices that are in the same iommu group as the supplied device from their current driver (except PCIe bridges).

2. Binds to vfio-pci:
  1. The supplied device.
  2. All unbound devices that have the same device_id and vendor_id as the supplied device.
  3. All devices that are in the same iommu group.

3. Transfers ownership of the respective iommu groups inside /dev/vfio to $SUDO_USER

__Script must be executed via sudo!__

##License##

See supplied LICENSE file.