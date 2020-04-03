# vfio-pci-bind

This script takes one or two parameters in any order:

- `Vendor:Device` i.e. `vvvv:dddd`
- `Domain:Bus:Device.Function` i.e. `dddd:vv:dd.f`

and then:

1. If both `Vendor:Device` and `Domain:Bus:Device.Function` were provided, validate that the requested `Vendor:Device` exists at `Domain:Bus:Device.Function`
   If only `Vendor:Device` was provided, determine the current `Domain:Bus:Device.Function` for that device.
   If only `Domain:Bus:Device.Function` was provided, use it.
2. Unbinds all devices that are in the same iommu group as the supplied device from their current driver (except PCIe bridges).
3. Binds to vfio-pci:
   1. The supplied device.
   2. All devices that are in the same iommu group.
4. Transfers ownership of the respective iommu group inside /dev/vfio to \$SUDO_USER

**Script must be executed via sudo!**

## License

See supplied LICENSE file.
