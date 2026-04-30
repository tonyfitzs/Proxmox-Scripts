#!/bin/bash

################################################################################
# Proxmox VM Provisioning Script for FlippiQ Infrastructure
# Author: Tony Fitzsimmons (tonyfitzs)
# Purpose: Provision Ansible, NFT test, and FlippiQ production VMs
# Version: 1.5
# License: MIT
################################################################################

################################################################################
# FUNCTIONS
################################################################################

function log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

function log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

function error_handler() {
  local line_number="$1"
  local command="$2"
  log_error "Command failed at line $line_number: $command"
  exit 1
}

function cleanup() {
  log_info "Cleanup complete"
}

function download_debian_iso() {
  local target_node="$1"
  local target_ip="${PROX_IPS[${target_node}]}"
  
  log_info "Downloading Debian 12 ISO to $target_node..."
  
  ssh -i "$PROX_SSH_KEY" "${PROX_SSH_USER}@${target_ip}" bash << 'DOWNLOAD_ISO'
ISO_PATH="/var/lib/vz/template/iso/debian-12.13.0-amd64-netinst.iso"

if [ -f "$ISO_PATH" ]; then
  echo "ISO already exists, skipping download"
else
  echo "Downloading Debian ISO..."
  cd /var/lib/vz/template/iso/
  wget -q "https://cdimage.debian.org/cdimage/archive/12.13.0/amd64/iso-cd/debian-12.13.0-amd64-netinst.iso"
  echo "ISO downloaded successfully"
fi
DOWNLOAD_ISO

  log_info "Debian ISO ready on $target_node"
}

function create_vm() {
  local vm_id="$1"
  local vm_name="$2"
  local cpu_cores="$3"
  local ram_mb="$4"
  local target_node="$5"
  local target_ip="${PROX_IPS[${target_node}]}"
  
  log_info "Creating VM $vm_id ($vm_name) on $target_node..."
  
  ssh -i "$PROX_SSH_KEY" "${PROX_SSH_USER}@${target_ip}" qm create $vm_id \
    --name $vm_name \
    --cores $cpu_cores \
    --memory $ram_mb \
    --machine q35 \
    --ostype l26 \
    --scsihw virtio-scsi-pci \
    --net0 virtio,bridge=vmbr0 \
    --boot order=ide2 \
    --ide2 local:iso/debian-12.13.0-amd64-netinst.iso,media=cdrom \
    --agent enabled=1 \
    --onboot 1
  
  log_info "VM $vm_id created successfully on $target_node"
}

function cleanup_iso() {
  local target_node="$1"
  local target_ip="${PROX_IPS[${target_node}]}"
  
  log_info "Cleaning up ISO from $target_node..."
  
  ssh -i "$PROX_SSH_KEY" "${PROX_SSH_USER}@${target_ip}" \
    rm -f /var/lib/vz/template/iso/debian-12.13.0-amd64-netinst.iso
  
  log_info "ISO cleanup complete"
}

function show_menu() {
  echo ""
  echo "===================================================="
  echo "Proxmox VM Provisioning - FlippiQ Infrastructure"
  echo "Author: Tony Fitzsimmons (tonyfitzs)"
  echo "===================================================="
  echo ""
  echo "Select server type to
