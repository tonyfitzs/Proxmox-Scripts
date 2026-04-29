#!/bin/bash

################################################################################
# Proxmox VM Provisioning Script
# Author: Tony Fitzsimmons (tonyfitzs)
# Repo:   https://github.com/tonyfitzs/proxmox-scripts
# Purpose: Provision FlippiQ, NFT, and Ansible VMs on a Proxmox cluster
#          with hardened SSH, static IPs, ZFS storage, and IPv6 disabled.
# License: MIT
#
# USAGE
#   bash <(curl -fsSL https://raw.githubusercontent.com/tonyfitzs/proxmox-scripts/main/provision-vm.sh)
#
# Or run locally after cloning the repo.
#
# PROTOTYPE — first pass. Expect iteration.
################################################################################

set -euo pipefail
IFS=$'\n\t'

#==============================================================================
# CONFIGURATION
#==============================================================================

SCRIPT_VERSION="0.1-prototype"

# --- Cluster topology -------------------------------------------------------
# Proxmox node hostnames (used for SSH) and their management IPs
declare -A PROX_IPS=(
  [prox-one]="10.110.10.3"
  [prox-two]="10.110.10.4"
  [prox-three]="10.110.10.5"
)

# VM ID series per node: prox-one => 1xx, prox-two => 2xx, prox-three => 3xx
declare -A PROX_ID_SERIES=(
  [prox-one]=100
  [prox-two]=200
  [prox-three]=300
)

# --- Network ----------------------------------------------------------------
GATEWAY="10.0.110.1"
DNS_PRIMARY="10.0.110.1"
DNS_SECONDARY="8.8.4.4"
SUBNET_CIDR="24"
BRIDGE="vmbr0"

# Static IPs for each role
declare -A ROLE_IPS=(
  [flippiq-prod]="10.110.10.6"
  [nft]="10.110.10.7"
  [ansible]="10.110.10.8"
)

# --- Storage ----------------------------------------------------------------
# Shared ZFS pool used for all VM disks (provides cluster redundancy)
STORAGE_POOL="zedpool"

# --- VM specs per role ------------------------------------------------------
# FlippiQ production (always on prox-one)
FLIPPIQ_NODE="prox-one"
FLIPPIQ_CORES=8
FLIPPIQ_RAM_MB=16384
FLIPPIQ_DISK_GB=400
FLIPPIQ_HOSTNAME="flippiq-prod"

# NFT non-functional test server (on prox-one — needs decent grunt for tests)
NFT_NODE="prox-one"
NFT_CORES=4
NFT_RAM_MB=8192
NFT_DISK_GB=100
NFT_HOSTNAME="nft-test"

# Ansible control node (on prox-two)
ANSIBLE_NODE="prox-two"
ANSIBLE_CORES=4
ANSIBLE_RAM_MB=8192
ANSIBLE_DISK_GB=50
ANSIBLE_HOSTNAME="ansible-ctrl"

# --- Local paths ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/keys"
LOG_FILE="${SCRIPT_DIR}/provisioning.log"

# Personal key (saved locally for PuTTY use)
USER_KEY_PRIV="${KEYS_DIR}/user_id"
USER_KEY_PUB="${KEYS_DIR}/user_id.pub"

# Ansible key — only PUBLIC saved locally; private is generated on Ansible VM
# in an obfuscated path.  Local pub copy is needed to inject into NFT/prod VMs.
ANSIBLE_KEY_PUB="${KEYS_DIR}/ansible_id.pub"

# --- Proxmox SSH ------------------------------------------------------------
# Tony: set PROX_SSH_KEY to the private key on this machine that can SSH into
# the Proxmox nodes as root.  Leave blank to use ssh-agent / default keys.
PROX_SSH_USER="root"
PROX_SSH_KEY="${PROX_SSH_KEY:-}"

# --- Cloud image ------------------------------------------------------------
# Debian 13 (Trixie) cloud image — uses cloud-init for first-boot config
DEBIAN_CODENAME="trixie"
DEBIAN_VERSION="13"
CLOUD_IMG_URL="https://cloud.debian.org/images/cloud/${DEBIAN_CODENAME}/latest/debian-${DEBIAN_VERSION}-generic-amd64.qcow2"

# Local user created inside each VM (no root login allowed over SSH)
VM_LOGIN_USER="adminops"

#==============================================================================
# HELPERS
#==============================================================================

log()  { echo "[$(date +'%H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
warn() { echo "[$(date +'%H:%M:%S')] WARN: $*" | tee -a "$LOG_FILE" >&2; }
fail() { echo "[$(date +'%H:%M:%S')] FAIL: $*" | tee -a "$LOG_FILE" >&2; exit 1; }

error_handler() {
  local line="$1" cmd="$2"
  warn "Error on line ${line}: ${cmd}"
}

cleanup() {
  : # placeholder — add temp file cleanup here if needed
}

# Run a command on a remote Proxmox node via SSH
prox_ssh() {
  local node="$1"; shift
  local host="${PROX_IPS[$node]}"
  local ssh_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
  [[ -n "$PROX_SSH_KEY" ]] && ssh_opts+=(-i "$PROX_SSH_KEY")
  ssh "${ssh_opts[@]}" "${PROX_SSH_USER}@${host}" "$@"
}

# Copy a file to a remote Proxmox node via SCP
prox_scp() {
  local src="$1" node="$2" dest="$3"
  local host="${PROX_IPS[$node]}"
  local scp_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
  [[ -n "$PROX_SSH_KEY" ]] && scp_opts+=(-i "$PROX_SSH_KEY")
  scp "${scp_opts[@]}" "$src" "${PROX_SSH_USER}@${host}:${dest}"
}

# Generate an obfuscated path for hiding SSH keys inside VMs.
# Looks like a legitimate system path — different per VM.
make_obfuscated_path() {
  local choices=(
    "/var/lib/systemd/coredump/.cache"
    "/var/lib/dpkg/.metadata-cache"
    "/var/cache/apt/archives/.partial-meta"
    "/usr/local/share/.font-cache"
    "/etc/.config-backup"
  )
  echo "${choices[RANDOM % ${#choices[@]}]}"
}

make_obfuscated_filename() {
  local choices=(libcache fontcfg metadata syscfg pkgindex)
  echo "${choices[RANDOM % ${#choices[@]}]}.dat"
}

#==============================================================================
# KEY MANAGEMENT
#==============================================================================

setup_keys_dir() {
  mkdir -p "$KEYS_DIR"
  chmod 700 "$KEYS_DIR"
  if [[ ! -f "${KEYS_DIR}/.gitignore" ]]; then
    cat > "${KEYS_DIR}/.gitignore" <<'EOF'
# Never commit private keys to GitHub
*
!.gitignore
EOF
    log "Wrote ${KEYS_DIR}/.gitignore"
  fi
}

ensure_user_keypair() {
  if [[ -f "$USER_KEY_PRIV" && -f "$USER_KEY_PUB" ]]; then
    log "User keypair already exists — keeping existing keys."
    return
  fi
  log "Generating personal SSH keypair at ${USER_KEY_PRIV}"
  ssh-keygen -t ed25519 -N "" -C "tonyfitzs@personal" -f "$USER_KEY_PRIV"
  chmod 600 "$USER_KEY_PRIV"
  chmod 644 "$USER_KEY_PUB"
}

# Ansible's keypair is generated INSIDE the Ansible VM during build, in an
# obfuscated path.  We capture only the PUBLIC key locally so we can later
# inject it into NFT and production VMs.
prepare_ansible_pubkey_placeholder() {
  if [[ ! -f "$ANSIBLE_KEY_PUB" ]]; then
    log "Ansible public key not yet present — will be generated when Ansible VM is built."
  else
    log "Ansible public key already captured at ${ANSIBLE_KEY_PUB}"
  fi
}

#==============================================================================
# VM ID ALLOCATION
#==============================================================================

# Find the next free VM ID in the correct series for the target node
next_vmid_for_node() {
  local node="$1"
  local series="${PROX_ID_SERIES[$node]}"
  local series_end=$((series + 99))

  # Get list of all in-use VM IDs across the cluster
  local in_use
  in_use=$(prox_ssh "$node" "pvesh get /cluster/resources --type vm --output-format json | jq -r '.[].vmid'")

  for ((id = series + 1; id <= series_end; id++)); do
    if ! grep -qw "$id" <<< "$in_use"; then
      echo "$id"
      return 0
    fi
  done
  fail "No free VM IDs in series ${series}xx on node ${node}"
}

#==============================================================================
# CLOUD-INIT USER-DATA BUILDERS
#==============================================================================

# Build cloud-init user-data for a STANDARD VM (FlippiQ prod or NFT).
# - Creates VM_LOGIN_USER with sudo NOPASSWD
# - Authorizes USER public key + Ansible public key
# - Hardens sshd: no root login, no password auth, key-only
# - Disables IPv6
# - Stores ansible authorized_keys in an obfuscated location
build_userdata_standard() {
  local hostname="$1"
  local user_pub ansible_pub
  user_pub=$(cat "$USER_KEY_PUB")
  ansible_pub=$(cat "$ANSIBLE_KEY_PUB")

  cat <<EOF
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true
preserve_hostname: false

users:
  - name: ${VM_LOGIN_USER}
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: true
    ssh_authorized_keys:
      - ${user_pub}
      - ${ansible_pub}

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - ca-certificates

write_files:
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    permissions: '0644'
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      PubkeyAuthentication yes
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      UsePAM yes
      AllowUsers ${VM_LOGIN_USER}
      X11Forwarding no
      PrintMotd no
  - path: /etc/sysctl.d/99-disable-ipv6.conf
    permissions: '0644'
    content: |
      net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1
      net.ipv6.conf.lo.disable_ipv6 = 1

runcmd:
  - systemctl enable --now qemu-guest-agent
  - sysctl --system
  - systemctl restart ssh
EOF
}

# Build cloud-init user-data for the ANSIBLE control node.
# Same hardening as standard, PLUS:
# - Installs ansible
# - Generates an Ansible keypair INSIDE the VM at an obfuscated path
# - Prints the public key to the serial console / cloud-init log so we can
#   capture it locally afterwards via `qm guest exec` or the script itself.
build_userdata_ansible() {
  local hostname="$1"
  local obf_dir obf_file
  obf_dir=$(make_obfuscated_path)
  obf_file=$(make_obfuscated_filename)
  local user_pub
  user_pub=$(cat "$USER_KEY_PUB")

  cat <<EOF
#cloud-config
hostname: ${hostname}
manage_etc_hosts: true
preserve_hostname: false

users:
  - name: ${VM_LOGIN_USER}
    groups: [sudo, docker]
    shell: /bin/bash
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    lock_passwd: true
    ssh_authorized_keys:
      - ${user_pub}

package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - curl
  - ca-certificates
  - ansible
  - python3-pip
  - jq

write_files:
  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    permissions: '0644'
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      PubkeyAuthentication yes
      KbdInteractiveAuthentication no
      ChallengeResponseAuthentication no
      UsePAM yes
      AllowUsers ${VM_LOGIN_USER}
      X11Forwarding no
      PrintMotd no
  - path: /etc/sysctl.d/99-disable-ipv6.conf
    permissions: '0644'
    content: |
      net.ipv6.conf.all.disable_ipv6 = 1
      net.ipv6.conf.default.disable_ipv6 = 1
      net.ipv6.conf.lo.disable_ipv6 = 1

runcmd:
  - systemctl enable --now qemu-guest-agent
  - sysctl --system
  - mkdir -p ${obf_dir}
  - chmod 700 ${obf_dir}
  - ssh-keygen -t ed25519 -N "" -C "ansible-ctrl" -f ${obf_dir}/${obf_file}
  - chmod 600 ${obf_dir}/${obf_file}
  - chmod 644 ${obf_dir}/${obf_file}.pub
  - cp ${obf_dir}/${obf_file}.pub /tmp/ansible_pubkey_export.pub
  - chmod 644 /tmp/ansible_pubkey_export.pub
  - echo "ANSIBLE_KEY_LOCATION=${obf_dir}/${obf_file}" >> /etc/environment
  - systemctl restart ssh
EOF
}

#==============================================================================
# VM PROVISIONING
#==============================================================================

# Download the Debian cloud image to the target Proxmox node (cached)
ensure_cloud_image_on_node() {
  local node="$1"
  local cache_path="/var/lib/vz/template/iso/debian-${DEBIAN_VERSION}-generic-amd64.qcow2"
  log "Ensuring cloud image is present on ${node}..."
  prox_ssh "$node" "test -s '$cache_path' || curl -fsSL -o '$cache_path' '$CLOUD_IMG_URL'"
  echo "$cache_path"
}

# Create a VM on the target node from cloud image + cloud-init user-data
create_vm() {
  local node="$1"
  local vmid="$2"
  local hostname="$3"
  local cores="$4"
  local ram_mb="$5"
  local disk_gb="$6"
  local static_ip="$7"
  local userdata_file="$8"

  local img_path
  img_path=$(ensure_cloud_image_on_node "$node")

  log "Creating VM ${vmid} (${hostname}) on ${node}..."

  # Upload user-data snippet to the node
  prox_ssh "$node" "mkdir -p /var/lib/vz/snippets"
  prox_scp "$userdata_file" "$node" "/var/lib/vz/snippets/${hostname}-user.yaml"

  # Create VM shell
  prox_ssh "$node" "qm create ${vmid} \
    --name ${hostname} \
    --memory ${ram_mb} \
    --cores ${cores} \
    --cpu host \
    --net0 virtio,bridge=${BRIDGE} \
    --ostype l26 \
    --agent enabled=1 \
    --machine q35 \
    --bios ovmf \
    --scsihw virtio-scsi-pci \
    --tags provisioned-by-tonyfitzs \
    --serial0 socket"

  # Import the cloud image as the VM's main disk on zedpool
  prox_ssh "$node" "qm importdisk ${vmid} ${img_path} ${STORAGE_POOL}"

  # Attach disk, EFI, cloud-init drive
  prox_ssh "$node" "qm set ${vmid} \
    --scsi0 ${STORAGE_POOL}:vm-${vmid}-disk-0,discard=on,ssd=1 \
    --efidisk0 ${STORAGE_POOL}:0,efitype=4m \
    --ide2 ${STORAGE_POOL}:cloudinit \
    --boot order=scsi0"

  # Resize disk to requested size
  prox_ssh "$node" "qm resize ${vmid} scsi0 ${disk_gb}G"

  # Cloud-init: static IP, nameservers, custom user-data
  prox_ssh "$node" "qm set ${vmid} \
    --ipconfig0 ip=${static_ip}/${SUBNET_CIDR},gw=${GATEWAY} \
    --nameserver '${DNS_PRIMARY} ${DNS_SECONDARY}' \
    --searchdomain local \
    --cicustom 'user=local:snippets/${hostname}-user.yaml'"

  log "VM ${vmid} configured. Starting..."
  prox_ssh "$node" "qm start ${vmid}"

  log "VM ${vmid} started. Waiting 60s for cloud-init to settle..."
  sleep 60
}

# After Ansible VM boots, retrieve its generated public key via guest agent
fetch_ansible_pubkey() {
  local node="$1"
  local vmid="$2"
  log "Fetching Ansible public key from VM ${vmid}..."

  # Use qm guest exec to read the exported pubkey
  local out
  out=$(prox_ssh "$node" "qm guest exec ${vmid} -- cat /tmp/ansible_pubkey_export.pub" 2>/dev/null || true)

  if [[ -n "$out" ]] && grep -q "ssh-ed25519" <<< "$out"; then
    # Extract the actual key line from the JSON-ish output
    grep -oE 'ssh-ed25519 [A-Za-z0-9+/=]+ [^"]*' <<< "$out" | head -n1 > "$ANSIBLE_KEY_PUB"
    log "Ansible public key saved to ${ANSIBLE_KEY_PUB}"
  else
    warn "Could not auto-fetch Ansible pubkey. SSH into the VM as ${VM_LOGIN_USER} and copy /tmp/ansible_pubkey_export.pub to ${ANSIBLE_KEY_PUB} manually."
  fi
}

#==============================================================================
# ROLE BUILDERS
#==============================================================================

build_ansible() {
  log "=== Building Ansible control node ==="
  local node="$ANSIBLE_NODE"
  local vmid; vmid=$(next_vmid_for_node "$node")
  local ip="${ROLE_IPS[ansible]}"
  local userdata; userdata=$(mktemp)
  build_userdata_ansible "$ANSIBLE_HOSTNAME" > "$userdata"

  create_vm "$node" "$vmid" "$ANSIBLE_HOSTNAME" \
    "$ANSIBLE_CORES" "$ANSIBLE_RAM_MB" "$ANSIBLE_DISK_GB" \
    "$ip" "$userdata"

  rm -f "$userdata"

  fetch_ansible_pubkey "$node" "$vmid"

  log "Ansible VM ready: ${ANSIBLE_HOSTNAME} (VMID ${vmid}) at ${ip}"
  log "  SSH:  ssh -i ${USER_KEY_PRIV} ${VM_LOGIN_USER}@${ip}"
}

build_flippiq() {
  if [[ ! -f "$ANSIBLE_KEY_PUB" ]]; then
    fail "Ansible pubkey not found at ${ANSIBLE_KEY_PUB}. Build the Ansible VM first."
  fi
  log "=== Building FlippiQ production VM ==="
  local node="$FLIPPIQ_NODE"
  local vmid; vmid=$(next_vmid_for_node "$node")
  local ip="${ROLE_IPS[flippiq-prod]}"
  local userdata; userdata=$(mktemp)
  build_userdata_standard "$FLIPPIQ_HOSTNAME" > "$userdata"

  create_vm "$node" "$vmid" "$FLIPPIQ_HOSTNAME" \
    "$FLIPPIQ_CORES" "$FLIPPIQ_RAM_MB" "$FLIPPIQ_DISK_GB" \
    "$ip" "$userdata"

  rm -f "$userdata"

  log "FlippiQ VM ready: ${FLIPPIQ_HOSTNAME} (VMID ${vmid}) at ${ip}"
  log "  SSH: ssh -i ${USER_KEY_PRIV} ${VM_LOGIN_USER}@${ip}"
}

build_nft() {
  if [[ ! -f "$ANSIBLE_KEY_PUB" ]]; then
    fail "Ansible pubkey not found at ${ANSIBLE_KEY_PUB}. Build the Ansible VM first."
  fi
  log "=== Building NFT test VM ==="
  local node="$NFT_NODE"
  local vmid; vmid=$(next_vmid_for_node "$node")
  local ip="${ROLE_IPS[nft]}"
  local userdata; userdata=$(mktemp)
  build_userdata_standard "$NFT_HOSTNAME" > "$userdata"

  create_vm "$node" "$vmid" "$NFT_HOSTNAME" \
    "$NFT_CORES" "$NFT_RAM_MB" "$NFT_DISK_GB" \
    "$ip" "$userdata"

  rm -f "$userdata"

  log "NFT VM ready: ${NFT_HOSTNAME} (VMID ${vmid}) at ${ip}"
  log "  SSH: ssh -i ${USER_KEY_PRIV} ${VM_LOGIN_USER}@${ip}"
}

#==============================================================================
# MAIN MENU
#==============================================================================

main_menu() {
  echo
  echo "================================================================"
  echo " Proxmox VM Provisioning Script  v${SCRIPT_VERSION}"
  echo " Author: Tony Fitzsimmons (tonyfitzs)"
  echo "================================================================"
  echo " 1) Build Ansible control node (prox-two, 200-series)"
  echo " 2) Build FlippiQ production  (prox-one, 100-series)"
  echo " 3) Build NFT test server     (prox-one, 100-series)"
  echo " 4) Build all three (Ansible -> FlippiQ -> NFT)"
  echo " 5) Show config and exit"
  echo " q) Quit"
  echo "================================================================"
  read -rp "Choice: " choice
  case "$choice" in
    1) build_ansible ;;
    2) build_flippiq ;;
    3) build_nft ;;
    4) build_ansible; build_flippiq; build_nft ;;
    5) show_config ;;
    q|Q) exit 0 ;;
    *) warn "Invalid choice." ; main_menu ;;
  esac
}

show_config() {
  echo
  echo "Cluster nodes:"
  for n in "${!PROX_IPS[@]}"; do
    echo "  ${n} => ${PROX_IPS[$n]}  (VMID series ${PROX_ID_SERIES[$n]}xx)"
  done
  echo
  echo "Static IPs:"
  for r in "${!ROLE_IPS[@]}"; do
    echo "  ${r} => ${ROLE_IPS[$r]}"
  done
  echo
  echo "Storage pool: ${STORAGE_POOL}"
  echo "Keys dir:     ${KEYS_DIR}"
  echo "Log file:     ${LOG_FILE}"
}

#==============================================================================
# ENTRY POINT
#==============================================================================

main() {
  setup_keys_dir
  ensure_user_keypair
  prepare_ansible_pubkey_placeholder
  log "Script started (v${SCRIPT_VERSION})"
  main_menu
  log "Done."
}

main "$@"
