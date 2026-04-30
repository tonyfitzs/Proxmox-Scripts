#!/bin/bash

################################################################################
# Proxmox VM Provisioning Script for FlippiQ Infrastructure
# Author: Tony Fitzsimmons (tonyfitzs)
# Purpose: Provision Ansible, NFT test, and FlippiQ production VMs
# Version: 1.7
# License: MIT
################################################################################

################################################################################
# CONFIGURATION (file scope - visible to all functions)
################################################################################

declare -A PROX_IPS=(
  [prox-one]="10.110.10.3"
  [prox-two]="10.110.10.4"
  [prox-three]="10.110.10.5"
)

GATEWAY="10.0.110.1"
DNS_PRIMARY="10.0.110.1"
DNS_SECONDARY="8.8.4.4"
SUBNET_MASK="24"

DEBIAN_ISO_URL="https://cdimage.debian.org/cdimage/archive/12.13.0/amd64/iso-cd/debian-12.13.0-amd64-netinst.iso"
DEBIAN_ISO_FILENAME="debian-12.13.0-amd64-netinst.iso"

# When run on a Proxmox node directly, just use root@localhost.
# Override by exporting PROX_SSH_KEY before running.
PROX_SSH_USER="root"
PROX_SSH_KEY="${PROX_SSH_KEY:-/root/.ssh/id_rsa}"

# Ansible Control Node
ANSIBLE_VM_ID="201"
ANSIBLE_NAME="ansible-ctrl"
ANSIBLE_CPU="4"
ANSIBLE_RAM="8192"
ANSIBLE_DISK="50"
ANSIBLE_TARGET_NODE="prox-two"
ANSIBLE_IP="10.110.10.8"

# NFT Test Server
NFT_VM_ID="101"
NFT_NAME="nft-test"
NFT_CPU="4"
NFT_RAM="8192"
NFT_DISK="100"
NFT_TARGET_NODE="prox-one"
NFT_IP="10.110.10.7"

# FlippiQ Production
FLIPPIQ_VM_ID="100"
FLIPPIQ_NAME="flippiq-prod"
FLIPPIQ_CPU="8"
FLIPPIQ_RAM="16384"
FLIPPIQ_DISK="400"
FLIPPIQ_TARGET_NODE="prox-one"
FLIPPIQ_IP="10.110.10.6"

################################################################################
# FUNCTIONS
################################################################################

log_info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $*"
}

log_error() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2
}

# Run a command on a Proxmox node. If we're already on that node, run locally.
prox_run() {
  local target_node="$1"
  shift
  local target_ip="${PROX_IPS[$target_node]}"
  local local_ip
  local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')

  if [ "$local_ip" = "$target_ip" ]; then
    bash -c "$*"
  else
    ssh -o StrictHostKeyChecking=accept-new -i "$PROX_SSH_KEY" \
      "${PROX_SSH_USER}@${target_ip}" "$@"
  fi
}

download_debian_iso() {
  local target_node="$1"
  log_info "Ensuring Debian 12 ISO is on $target_node..."

  prox_run "$target_node" "
    ISO_PATH=/var/lib/vz/template/iso/${DEBIAN_ISO_FILENAME}
    if [ -f \"\$ISO_PATH\" ]; then
      echo 'ISO already exists, skipping download'
    else
      echo 'Downloading Debian ISO...'
      cd /var/lib/vz/template/iso/ && wget -q '${DEBIAN_ISO_URL}'
      echo 'ISO downloaded successfully'
    fi
  "
  log_info "Debian ISO ready on $target_node"
}

create_vm() {
  local vm_id="$1"
  local vm_name="$2"
  local cpu_cores="$3"
  local ram_mb="$4"
  local target_node="$5"

  log_info "Creating VM $vm_id ($vm_name) on $target_node..."

  prox_run "$target_node" "qm create $vm_id \
    --name $vm_name \
    --cores $cpu_cores \
    --memory $ram_mb \
    --machine q35 \
    --ostype l26 \
    --scsihw virtio-scsi-pci \
    --net0 virtio,bridge=vmbr0 \
    --boot order=ide2 \
    --ide2 local:iso/${DEBIAN_ISO_FILENAME},media=cdrom \
    --agent enabled=1 \
    --onboot 1"

  log_info "VM $vm_id created on $target_node"
}

cleanup_iso() {
  local target_node="$1"
  log_info "Cleaning up ISO from $target_node..."
  prox_run "$target_node" "rm -f /var/lib/vz/template/iso/${DEBIAN_ISO_FILENAME}"
  log_info "ISO cleanup complete"
}

show_menu() {
  echo ""
  echo "===================================================="
  echo " Proxmox VM Provisioning - FlippiQ Infrastructure"
  echo " Author: Tony Fitzsimmons (tonyfitzs)"
  echo " Version: 1.7"
  echo "===================================================="
  echo ""
  echo "  1) Ansible Control Node (prox-two, VMID 201)"
  echo "  2) NFT Test Server      (prox-one, VMID 101)"
  echo "  3) FlippiQ Production   (prox-one, VMID 100)"
  echo "  4) Exit"
  echo ""
  # Critical: read from /dev/tty so this works when run via bash <(curl ...)
  read -p "Enter choice [1-4]: " choice < /dev/tty
}

build_ansible() {
  log_info "Building Ansible Control Node..."
  download_debian_iso "$ANSIBLE_TARGET_NODE"
  create_vm "$ANSIBLE_VM_ID" "$ANSIBLE_NAME" "$ANSIBLE_CPU" "$ANSIBLE_RAM" "$ANSIBLE_TARGET_NODE"
  log_info "VM $ANSIBLE_VM_ID created. Open the Proxmox console to install Debian."
  read -p "Press Enter after OS installation is complete (or Ctrl+C to skip cleanup): " _ < /dev/tty
  cleanup_iso "$ANSIBLE_TARGET_NODE"
}

build_nft() {
  log_info "Building NFT Test Server..."
  download_debian_iso "$NFT_TARGET_NODE"
  create_vm "$NFT_VM_ID" "$NFT_NAME" "$NFT_CPU" "$NFT_RAM" "$NFT_TARGET_NODE"
  log_info "VM $NFT_VM_ID created. Open the Proxmox console to install Debian."
  read -p "Press Enter after OS installation is