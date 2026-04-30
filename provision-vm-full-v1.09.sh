#!/bin/bash

################################################################################
# Proxmox VM Provisioning Script for FlippiQ Infrastructure
# Author: Tony Fitzsimmons (tonyfitzs)
# Purpose: Provision Ansible, NFT, and FlippiQ VMs with Docker
# Based on community-scripts docker-vm.sh
# Version: 1.09
# License: MIT
################################################################################

source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/api.func) 2>/dev/null
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/vm-core.func) 2>/dev/null
source <(curl -fsSL https://git.community-scripts.org/community-scripts/ProxmoxVE/raw/branch/main/misc/cloud-init.func) 2>/dev/null || true
load_functions

################################################################################
# CONFIGURATION
################################################################################

APP="Docker"
APP_TYPE="vm"
NSAPP="docker-vm"
var_os="debian"
OS_TYPE="debian"
var_version="12"

GEN_MAC=02:$(openssl rand -hex 5 | awk '{print toupper($0)}' | sed 's/\(..\)/\1:/g; s/.$//')
RANDOM_UUID="$(cat /proc/sys/kernel/random/uuid)"
METHOD="default"
DISK_CACHE=""
MACHINE=" -machine q35"
CPU_TYPE=" -cpu host"
BRG="vmbr0"
VLAN=""
MTU=""
START_VM="yes"
THIN="discard=on,ssd=1,"

# Storage
STORAGE="zpool"

# SSH Public Key (set this to your public key)
SSH_PUBLIC_KEY="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCw02bxFxR5DE2k0ihoQ8D7uE4oj4q+BZ7xBwEQGWOGau0jruDoAktmayzhnsmfdpj8Xg5rkctTSJscFTwINTu1AslwGv52NGHwNlRM9JtqPPtGEZzixXy2HJLqw9IMZUQP9nkDOS8H9bKTdaVdVgxUQP6elpIJJxhHDY2Ep9PQ1UNgGt2dMVgjznx2t7BSkf4Kdzb1l2D920I/8/Dy1r4WSxB0BOmAKYs7Z5TMXCckTFra0tw1JWXKFHVY/0oaPKOtX+aL+2Y7uMmiDrTTSaSp0Rl4uJwVxqrRymCm8MNadgFGRrR82MkhwW36LqaAkWwDuU8brhnLMCwyOuA4mtvl rsa-key-20260430"

# Network configuration
GATEWAY="10.0.110.1"
DNS_PRIMARY="10.0.110.1"
DNS_SECONDARY="8.8.4.4"
SUBNET_MASK="24"

# Server specs - Ansible
ANSIBLE_VMID="201"
ANSIBLE_HOSTNAME="ansible-ctrl"
ANSIBLE_CORES="4"
ANSIBLE_RAM="8192"
ANSIBLE_DISK="50G"
ANSIBLE_IP="10.110.10.8"
ANSIBLE_NODE="prox-two"

# Server specs - NFT
NFT_VMID="101"
NFT_HOSTNAME="nft-test"
NFT_CORES="4"
NFT_RAM="8192"
NFT_DISK="100G"
NFT_IP="10.110.10.7"
NFT_NODE="prox-one"

# Server specs - FlippiQ
FLIPPIQ_VMID="100"
FLIPPIQ_HOSTNAME="flippiq-prod"
FLIPPIQ_CORES="8"
FLIPPIQ_RAM="16384"
FLIPPIQ_DISK="400G"
FLIPPIQ_IP="10.110.10.6"
FLIPPIQ_NODE="prox-one"

################################################################################
# FUNCTIONS
################################################################################

log_info() {
  echo "[INFO] $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

show_menu() {
  echo ""
  echo "===================================================="
  echo "Proxmox VM Provisioning - FlippiQ Infrastructure"
  echo "Version: 1.08"
  echo "Author: Tony Fitzsimmons (tonyfitzs)"
  echo "===================================================="
  echo ""
  echo "Select server type to provision:"
  echo ""
  echo "  1) Ansible Control Node   (prox-two, VMID 201, 50GB)"
  echo "  2) NFT Test Server        (prox-one, VMID 101, 100GB)"
  echo "  3) FlippiQ Production     (prox-one, VMID 100, 400GB)"
  echo "  4) Exit"
  echo ""
  read -p "Enter choice [1-4]: " choice < /dev/tty
}

function select_cloud_init() {
  if [ "$OS_TYPE" = "ubuntu" ]; then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes (Ubuntu requires Cloud-Init)${CL}"
    return
  fi

  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "CLOUD-INIT" \
    --yesno "Enable Cloud-Init for VM configuration?\n\nCloud-Init allows automatic configuration of:\n- User accounts and passwords\n- SSH keys\n- Network settings (DHCP/Static)\n- DNS configuration\n\nYou can also configure these settings later in Proxmox UI.\n\nNote: Debian without Cloud-Init will use nocloud image with console auto-login." 18 68); then
    USE_CLOUD_INIT="yes"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}yes${CL}"
  else
    USE_CLOUD_INIT="no"
    echo -e "${CLOUD:-${TAB}☁️${TAB}${CL}}${BOLD}${DGN}Cloud-Init: ${BGN}no${CL}"
  fi
}
provision_vm() {
  local VMID="$1"
  local HOSTNAME="$2"
  local CORES="$3"
  local RAM="$4"
  local DISK="$5"
  local STATIC_IP="$6"

  select_cloud_init
  
  msg_info "Provisioning VM $VMID ($HOSTNAME) with Docker"
  
  # Create cloud-init user data with SSH key and network config
  local CLOUD_INIT_USER_DATA="
#cloud-config
hostname: $HOSTNAME
fqdn: $HOSTNAME.local
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - ca-certificates

users:
  - name: adminops
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: docker
    shell: /bin/bash
    ssh-authorized-keys:
      - $SSH_PUBLIC_KEY

runcmd:
  - curl -fsSL https://get.docker.com | sh
  - systemctl enable docker
  - systemctl start docker
  - usermod -aG docker adminops
  - netplan apply

write_files:
  - path: /etc/netplan/00-installer-config.yaml
    content: |
      network:
        version: 2
        ethernets:
          eth0:
            dhcp4: false
            addresses:
              - $STATIC_IP/$SUBNET_MASK
            gateway4: $GATEWAY
            nameservers:
              addresses: [$DNS_PRIMARY, $DNS_SECONDARY]
"

  # Create temporary cloud-init file
  local CLOUD_INIT_FILE="/tmp/cloud-init-$VMID.txt"
  echo "$CLOUD_INIT_USER_DATA" > "$CLOUD_INIT_FILE"
  
  # Create VM
  msg_info "Creating VM $VMID"
  qm create $VMID \
    --name $HOSTNAME \
    --cores $CORES \
    --memory $RAM \
    --machine q35 \
    --ostype l26 \
    --scsihw virtio-scsi-pci \
    --net0 virtio,bridge=$BRG \
    --boot order=scsi0 \
    --agent enabled=1 \
    --onboot 1 \
    --tags community-script

  msg_info "Importing disk image"
  # Download and import Debian 13 cloud image
  local IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
  local IMAGE_FILE="/tmp/debian-12-generic-amd64.qcow2"
  
  if [ ! -f "$IMAGE_FILE" ]; then
    curl -fsSL -o "$IMAGE_FILE" "$IMAGE_URL"
  fi
  
  # Import disk to zpool
  qm importdisk $VMID "$IMAGE_FILE" $STORAGE --format qcow2
  
  # Attach disk
  qm set $VMID --scsi0 $STORAGE:vm-$VMID-disk-0
  
  # Add cloud-init
  qm set $VMID --cicustom "user=local:snippets/cloud-init-$VMID"
  
  # Upload cloud-init config
  mkdir -p /var/lib/vz/snippets
  cp "$CLOUD_INIT_FILE" "/var/lib/vz/snippets/cloud-init-$VMID"
  
  # Clean up
  rm -f "$CLOUD_INIT_FILE" "$IMAGE_FILE"
  
  msg_ok "VM $VMID ($HOSTNAME) created successfully"
  msg_ok "Static IP: $STATIC_IP"
  msg_ok "Start VM and wait for cloud-init to complete"
}

################################################################################
# MAIN
################################################################################

main() {
  while true; do
    show_menu
    
    case $choice in
      1)
        provision_vm "$ANSIBLE_VMID" "$ANSIBLE_HOSTNAME" "$ANSIBLE_CORES" "$ANSIBLE_RAM" "$ANSIBLE_DISK" "$ANSIBLE_IP"
        ;;
      2)
        provision_vm "$NFT_VMID" "$NFT_HOSTNAME" "$NFT_CORES" "$NFT_RAM" "$NFT_DISK" "$NFT_IP"
        ;;
      3)
        provision_vm "$FLIPPIQ_VMID" "$FLIPPIQ_HOSTNAME" "$FLIPPIQ_CORES" "$FLIPPIQ_RAM" "$FLIPPIQ_DISK" "$FLIPPIQ_IP"
        ;;
      4)
        msg_info "Exiting..."
        exit 0
        ;;
      *)
        echo "Invalid choice. Please try again."
        ;;
    esac
  done
}

main "$@"
