#!/bin/bash

################################################################################
# Proxmox VM Provisioning Script for FlippiQ Infrastructure
# Author: Tony Fitzsimmons (tonyfitzs)
# Purpose: Provision Ansible, NFT test, and FlippiQ production VMs
# Version: 1.7
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

# Proxmox cluster nodes
declare -A PROX_IPS=(
  [prox-one]="10.110.10.3"
  [prox-two]="10.110.10.4"
  [prox-three]="10.110.10.5"
)

# Network configuration
GATEWAY="10.0.110.1"
DNS_PRIMARY="10.0.110.1"
DNS_SECONDARY="8.8.4.4"
SUBNET_MASK="24"

# Debian 12 ISO
DEBIAN_ISO_URL="https://cdimage.debian.org/cdimage/archive/12.13.0/amd64/iso-cd/debian-12.13.0-amd64-netinst.iso"
DEBIAN_ISO_FILENAME="debian-12.13.0-amd64-netinst.iso"

# SSH configuration
PROX_SSH_USER="root"