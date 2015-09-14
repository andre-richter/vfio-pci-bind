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
# This script takes a Bus:Device:Function string of the form "00:00.0"
# as command line argument and:
#
#  (1) Unbinds all devices that are in the same iommu group as the supplied
#      device from their current driver (except PCIe bridges).
#
#  (2) Binds to vfio-pci:
#    (2.1) The supplied device.
#    (2.2) All unbound devices that have the same device_id and vendor_id as
#          the supplied device.
#    (2.3) All devices that are in the same iommu group.
#
#  (3) Transfers ownership of the respective iommu groups inside /dev/vfio
#      to $SUDO_USER
#
# Script must be executed via sudo

unless ENV['USER'] == 'root'
  puts 'Please execute the script as root.'
  exit
end

unless File.exist?('/sys/bus/pci/devices/0000:00:00.0/iommu/')
  puts 'No signs of an IOMMU. Check your hardware and/or linux cmdline parameters.'
  puts 'Use intel_iommu=on or iommu=pt iommu=1'
  exit
end

bdf = nil
ARGV.each do |a|
  bdf = a[0..6] if a[0..6] =~ /\h\h\:\h\h\.\h/
end

if bdf.nil?
  puts 'Please supply B:D:F of PCIe device in form: 00:00.0'
  exit
end

TARGET_DEV_SYSFS_PATH = "/sys/bus/pci/devices/0000:#{bdf}/"

unless File.exist?(TARGET_DEV_SYSFS_PATH)
  puts 'There is no such device'
  exit
end

# Check if other devices share the same iommu group
dev_sysfs_paths = Dir.glob(TARGET_DEV_SYSFS_PATH + 'iommu_group/devices/*')

# Do not care about bridges
dev_sysfs_paths.delete_if { |dsp| File.read(dsp + '/class')[0..5] == '0x0604' }

puts "\nIOMMU group population:"
puts dev_sysfs_paths

`modprobe vfio-pci`
fail 'Error probing vfio-pci' unless $?.success?

dev_sysfs_paths.each do |dsp|

  dpath = dsp + '/driver'
  dbdf = dsp.split('/').last
  devid = File.read(dsp + '/vendor').strip + ' ' +
          File.read(dsp + '/device').strip
  
  # Unbind device if bound to a driver other than vfio-pci
  if File.exist?(dpath)
    curr_driver = File.readlink(dpath).split('/').last

    next if curr_driver == 'vfio-pci'
   
    File.write(dpath + '/unbind', dbdf)
    puts "Unbound #{dbdf} from #{curr_driver}"
  end

  # Add id to vfio-pci driver
  File.write('/sys/bus/pci/drivers/vfio-pci/new_id', devid)

  puts "Added #{dbdf} to vfio-pci"
end

print "\n"

# Adjust ownership
ids = ENV['SUDO_UID'] + ':' + ENV['SUDO_GID']
Dir.glob('/dev/vfio/[0-9]*').each { |f| `chown #{ids} #{f}` }

puts "success...\n\n"
puts 'ls -l /sys/bus/pci/drivers/vfio-pci'
puts `ls -l /sys/bus/pci/drivers/vfio-pci`
puts "\n\nls -l /dev/vfio/"
puts `ls -l /dev/vfio/`
