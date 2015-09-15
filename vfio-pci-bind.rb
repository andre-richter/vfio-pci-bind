#!/usr/bin/env ruby
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

unless ENV['USER'] == 'root'
  puts 'Please execute the script as root/via sudo.'
  exit
end

bdf = nil
if ARGV[0][0..6] =~ /\h\h\:\h\h\.\h/
  bdf = '0000:' + ARGV[0][0..6]
  puts "Warning: You did not supply a PCI domain, assuming #{bdf}"
else
  bdf = ARGV[0][0..11] if ARGV[0][0..11] =~ /\h\h\h\h\:\h\h\:\h\h\.\h/
end

if bdf.nil?
  puts 'Please supply Domain:Bus:Device.Function of PCI device in form: dddd:bb:dd.f'
  exit
end

TARGET_DEV_SYSFS_PATH = "/sys/bus/pci/devices/#{bdf}"

unless File.exist?(TARGET_DEV_SYSFS_PATH)
  puts 'There is no such device'
  exit
end

unless File.exist?(TARGET_DEV_SYSFS_PATH + '/iommu')
  puts 'No signs of an IOMMU. Check your hardware and/or linux cmdline parameters.'
  puts 'Use intel_iommu=on or iommu=pt iommu=1'
  exit
end

# Check if other devices share the same iommu group
dev_sysfs_paths = Dir.glob(TARGET_DEV_SYSFS_PATH + '/iommu_group/devices/*')

# Do not care about bridges; Identify by checking HEADER TYPE != 0 in PCI configuration space
dev_sysfs_paths.delete_if { |dsp| (File.read(dsp + '/config', 1, 0xe).unpack('C')[0] & 0x7f) != 0 }

puts "\nIOMMU group members (sans bridges):"
puts dev_sysfs_paths

`modprobe -i vfio-pci`
fail 'Error probing vfio-pci' unless $?.success?

puts "\nBinding..."
dev_sysfs_paths.each do |dsp|
  dpath = dsp + '/driver'
  dbdf = dsp.split('/').last

  File.write(dsp + '/driver_override', 'vfio-pci')

  if File.exist?(dpath)
    curr_driver = File.readlink(dpath).split('/').last

    if curr_driver == 'vfio-pci'
      puts "#{dbdf} already bound to vfio-pci"
      next
    else
      File.write(dpath + '/unbind', dbdf)
      puts "Unbound #{dbdf} from #{curr_driver}"
    end
  end

  File.write('/sys/bus/pci/drivers_probe', dbdf)
end

print "\n"

# Adjust group ownership
iommu_group = File.readlink(TARGET_DEV_SYSFS_PATH + '/iommu_group').split('/').last
user_and_group = ENV['SUDO_UID'] + ':' + ENV['SUDO_GID']
`chown #{user_and_group} /dev/vfio/#{iommu_group}`
fail 'Error adjusting group ownership' unless $?.success?

puts "success...\n\n"
puts 'Devices listed in /sys/bus/pci/drivers/vfio-pci:'
`ls -l /sys/bus/pci/drivers/vfio-pci`.each_line do |l|
  puts l if l =~ /\h\h\h\h\:/
end
puts "\nls -l /dev/vfio/"
puts `ls -l /dev/vfio/`
