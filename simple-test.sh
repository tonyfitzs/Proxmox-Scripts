#!/bin/bash

# Simple Proxmox VM Creation Script
# Creates a basic VM on prox-two with Debian 12 ISO

set -e

# Configuration
PROX_NODE="prox-two"
PROX_IP="10.110.10.4"
PROX_USER="root"
PROX_SSH_KEY="${PROX_SSH_KEY:-/path/to/proxmox/private/key}"

VM_ID="201"
VM_NAME="debian-test"
CPU_CORES="4"
RAM_MB="8192"
STORAGE="local-lvm"
ISO_PATH="local:iso/debian-12.13.0-amd64-netinst.iso"

echo "Creating VM $VM_ID on $PROX_NODE..."

ssh -i "$PROX_SSH_KEY" "${PROX_USER}@${PROX_IP}" qm create $VM_ID \
  --name $VM_NAME \
  --cores $CPU_CORES \
  --memory $RAM_MB \
  --machine q35 \
  --ostype l26 \
  --scsihw virtio-scsi-pci \
  --net0 virtio,bridge=vmbr0 \
  --boot order=ide2 \
  --ide2 ${ISO_PATH},media=cdrom \
  --agent enabled=1 \
  --onboot 1

echo "VM $VM_ID created successfully"
echo "Boot from ISO and install manually"