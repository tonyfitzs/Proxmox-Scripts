#!/bin/bash

################################################################################
# Proxmox VM Provisioning Script for FlippiQ Infrastructure
# Author: Tony Fitzsimmons (tonyfitzs)
# Purpose: Provision Ansible, NFT test, and FlippiQ production VMs
# Based on working simple-test.sh baseline
# Version: 1.1
# License: MIT
################################################################################

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

################################################################################
# CONFIGURATION
################################################################################

# Proxmox cluster nodes
declare -A PROX_IPS=(
  [prox-one]="10.110.10.3"
  [prox-two]="10.110.10.4"
  [prox-three]="10.110.10.5"
)

declare -A PROX_ID_SERIES=(
  [prox-one]="100"
  [prox-two]="200"
  [prox-three]="300"
)

# Network configuration
GATEWAY="10.0.110.1"
DNS_PRIMARY="10.0.110.1"
DNS_SECONDARY="8.8.4.4"
SUBNET_MASK="24"

# Debian 12 ISO
DEBIAN_ISO_URL="https://cdimage.debian.org/cdimage/archive/12.13.0/amd64/iso-cd/debian-12.13.0-amd64-netinst.iso"
DEBIAN_ISO_FILENAME="debian-12.13.0-amd64-netinst.iso"
ISO_STORAGE_PATH="/var/lib/vz/template/iso"

# SSH configuration
PROX_SSH_USER="root"
PROX_SSH_KEY="${PROX_SSH_KEY:-/path/to/proxmox/private/key}"

# Storage
STORAGE_LOCAL="local-lvm"
STORAGE_SHARED="zpool"

# Ansible Control Node
ANSIBLE_VM_ID="201"
ANSIBLE_NAME="ansible-ctrl"
ANSIBLE_CPU="4"
ANSIBLE_RAM="8192"
ANSIBLE_DISK="50"
ANSIBLE_TARGET_NODE="prox-two"
ANSIBLE_IP="10.110.10.8"

# NFT Test Server
NFT_VM_ID="102"
NFT_NAME="nft-test"
NFT_CPU="4"
NFT_RAM="8192"
NFT_DISK="100"
NFT_TARGET_NODE="prox-one"
NFT_IP="10.110.10.7"

# FlippiQ Production
FLIPPIق_VM_ID="101"
FLIPPIق_NAME="flippiق-prod"
FLIPPIق_CPU="8"
FLIPPIق_RAM="16384"
FLIPPIق_DISK="400"
FLIPPIق_TARGET_NODE="prox-one"
FLIPPIق_IP="10.110.10.6"

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
  
  ssh -i "$PROX_SSH_KEY" "${PROX_SSH_USER}@${target_ip}" bash << 'SSH_COMMANDS'
DEBIAN_ISO_FILENAME="debian-12.13.0-amd64-netinst.iso"
ISO_PATH="/var/lib/vz/template/iso/${DEBIAN_ISO_FILENAME}"

if [ -f "$ISO_PATH" ]; then
  echo "ISO already exists, skipping download"
else
  echo "Downloading Debian ISO..."
  cd /var/lib/vz/template/iso/
  wget -q "https://cdimage.debian.org/cdimage/archive/12.13.0/amd64/iso-cd/debian-12.13.0-amd64-netinst.iso"
  echo "ISO downloaded successfully"
fi
SSH_COMMANDS

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