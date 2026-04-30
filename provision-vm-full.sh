#!/bin/bash

################################################################################
# Proxmox VM Provisioning Script for FlippiQ Infrastructure
# Author: Tony Fitzsimmons (tonyfitzs)
# Purpose: Provision Ansible, NFT test, and FlippiQ production VMs
# Version: 1.6
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
  echo "Select server type to provision:"
  echo ""
  echo "  1) Ansible Control Node (prox-two, 201)"
  echo "  2) NFT Test Server (prox-one, 101)"
  echo "  3) FlippiQ Production (prox-one, 100)"
  echo "  4) Exit"
  echo ""
  read -p "Enter choice [1-4]: " choice
}

function main() {
  set -e
  trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
  trap cleanup EXIT

  declare -A PROX_IPS=(
    [prox-one]="10.110.10.3"
    [prox-two]="10.110.10.4"
    [prox-three]="10.110.10.5"
  )

  PROX_SSH_USER="root"
  PROX_SSH_KEY="${PROX_SSH_KEY:-/path/to/proxmox/private/key}"

  ANSIBLE_VM_ID="201"
  ANSIBLE_NAME="ansible-ctrl"
  ANSIBLE_CPU="4"
  ANSIBLE_RAM="8192"
  ANSIBLE_TARGET_NODE="prox-two"

  NFT_VM_ID="101"
  NFT_NAME="nft-test"
  NFT_CPU="4"
  NFT_RAM="8192"
  NFT_TARGET_NODE="prox-one"

  FLIPPIQ_VM_ID="100"
  FLIPPIQ_NAME="flippiq-prod"
  FLIPPIQ_CPU="8"
  FLIPPIQ_RAM="16384"
  FLIPPIQ_TARGET_NODE="prox-one"

  while true; do
    show_menu
    
    case $choice in
      1)
        log_info "Building Ansible Control Node..."
        download_debian_iso "$ANSIBLE_TARGET_NODE"
        create_vm "$ANSIBLE_VM_ID" "$ANSIBLE_NAME" "$ANSIBLE_CPU" "$ANSIBLE_RAM" "$ANSIBLE_TARGET_NODE"
        log_info "VM $ANSIBLE_VM_ID created"
        read -p "Press Enter after OS installation is complete: "
        cleanup_iso "$ANSIBLE_TARGET_NODE"
        ;;
      2)
        log_info "Building NFT Test Server..."
        download_debian_iso "$NFT_TARGET_NODE"
        create_vm "$NFT_VM_ID" "$NFT_NAME" "$NFT_CPU" "$NFT_RAM" "$NFT_TARGET_NODE"
        log_info "VM $NFT_VM_ID created"
        read -p "Press Enter after OS installation is complete: "
        cleanup_iso "$NFT_TARGET_NODE"
        ;;
      3)
        log_info "Building FlippiQ Production Server..."
        download_debian_iso "$FLIPPIQ_TARGET_NODE"
        create_vm "$FLIPPIQ_VM_ID" "$FLIPPIQ_NAME" "$FLIPPIQ_CPU" "$FLIPPIQ_RAM" "$FLIPPIQ_TARGET_NODE"
        log_info "VM $FLIPPIQ_VM_ID created"
        read -p "Press Enter after OS installation is complete: "
        cleanup_iso "$FLIPPIQ_TARGET_NODE"
        ;;
      4)
        log_info "Exiting..."
        exit 0
        ;;
      *)
        echo "Invalid choice. Please try again."
        ;;
    esac
  done
}

# Start the script
main "$@"
