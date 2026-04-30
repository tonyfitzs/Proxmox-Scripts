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

set -e
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR
trap cleanup EXIT

################################################################################
# CONFIGURATION
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

PROX_SSH_USER="root"
PROX_SSH_KEY="${PROX_SSH_KEY:-/path/to/proxmox/private/key}"

STORAGE_LOCAL="local-lvm"
STORAGE_SHARED="zpool"

ANSIBLE_VM_ID="201"
ANSIBLE_NAME="ansible-ctrl"
ANSIBLE_CPU="4"
ANSIBLE_RAM="8192"
ANSIBLE_DISK="50"
ANSIBLE_TARGET_NODE="prox-two"
ANSIBLE_IP="10.110.10.8"

NFT_VM_ID="101"
NFT_NAME="nft-test"
NFT_CPU="4"
NFT_RAM="8192"
NFT_DISK="100"
NFT_TARGET_NODE="prox-one"
NFT_IP="10.110.10.7"

FLIPPIQ_VM_ID="100"
FLIPPIQ_NAME="flippiq-prod"
FLIPPIQ_CPU="8"
FLIPPIQ_RAM="16384"
FLIPPIQ_DISK="400"
