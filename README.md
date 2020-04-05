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

Suggestions:

- If you have a single piece of hardware with a given `Vendor:Device`, you can call the script like this:

  `vfio-pci-bind.sh Vendor:Device`

  The script will target that device regardless of how the PCI address might change due to the addition or removal of other hardware.

- If you have multiple pieces of hardware with the same `Vendor:Device` code, you need to pass the PCI address as well:

  `vfio-pci-bind.sh Vendor:Device Domain:Bus:Device.Function`

  This will ensure the correct instance of the hardware is bound to vfio-pci.

  Note: If the PCI address for this device changes as a result of adding or removing hardware, you will need to update the PCI address in this call.

- For backwards compatibility you can also specify just the PCI address:

  `vfio-pci-bind.sh Domain:Bus:Device.Function`

  Note: If you add or remove hardware, the device associated with that PCI address can change resulting in the wrong device being bound to vfio-pci. Consider passing the `Vendor:Device` as well.

**Script must be executed via sudo!**

## License

See supplied LICENSE file.
