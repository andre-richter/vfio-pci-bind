# vfio-pci-bind

This script takes two parameters:

- `Domain:Bus:Device.Function` (required) i.e. `0000:00:00.0`
- `Vendor:Device` (optional) i.e. `0000:0000`

and then:

1. Verifies that the optional `Vendor:Device` matches the Vendor:Device currently at the requested `Domain:Bus:Device.Function` PCI address. If they do not match, exit without binding the requested PCI address. The goal is to prevent the wrong device from being bound to vfio-pci after a hardware change.
2. Unbinds all devices that are in the same iommu group as the supplied device from their current driver (except PCIe bridges).
3. Binds to vfio-pci:
   1. The supplied device.
   2. All devices that are in the same iommu group.
4. Transfers ownership of the respective iommu group inside /dev/vfio to \$SUDO_USER

**Script must be executed via sudo!**

## License

See supplied LICENSE file.
