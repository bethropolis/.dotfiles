#!/bin/bash

VM_NAME="win11"
LIBVIRT_URI="qemu:///system"

# Check if VM is already running
if virsh --connect="${LIBVIRT_URI}" list --name | grep -q "^${VM_NAME}$"; then
  echo "VM '${VM_NAME}' is already running. Connecting to it..."
  virt-viewer --connect "${LIBVIRT_URI}" "${VM_NAME}" &
  exit 0
fi

# Start the VM
echo "Starting VM '${VM_NAME}'..."
virsh --connect="${LIBVIRT_URI}" start "${VM_NAME}"

# Wait a moment for the VM to initialize
sleep 2

# Launch virt-viewer to connect to the VM
virt-viewer --connect "${LIBVIRT_URI}" "${VM_NAME}" &

echo "VM '${VM_NAME}' started and viewer launched."
