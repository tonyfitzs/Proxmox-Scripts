# Proxmox VM Provisioning Scripts

Automated provisioning of FlippiQ production, NFT test, and Ansible control VMs on a Proxmox cluster with hardened SSH, static networking, and zpool storage.

**Author:** Tony Fitzsimmons (tonyfitzs)
**License:** MIT

---

## Quick Start

To provision a VM, SSH into any Proxmox node and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonyfitzs/proxmox-scripts/main/provision-vm.sh)
```

Follow the interactive menu to select your server type and provide configuration details.

---

## Prerequisites

- SSH key-based access to all Proxmox nodes (prox-one, prox-two, prox-three)
- The script requires root access on the target Proxmox node
- Set the `PROX_SSH_KEY` environment variable to point to your Proxmox private key:
```bash
export PROX_SSH_KEY=/path/to/your/proxmox/private/key
```

---

## Server Types

### 1. FlippiQ Production
- **Target Node:** prox-one (fixed)
- **VM ID Series:** 100-series
- **CPU:** 8 cores
- **RAM:** 16 GB
- **Disk:** 400 GB on zpool
- **Static IP:** 10.110.10.6
- **Use Case:** Production deployment of FlippiQ platform

### 2. NFT Test Server
- **Target Node:** prox-one
- **VM ID Series:** 100-series
- **CPU:** Customizable (default 4 cores)
- **RAM:** Customizable (default 8 GB)
- **Disk:** Customizable (default 100 GB)
- **Static IP:** 10.110.10.7
- **Use Case:** Non-functional testing, security scanning, performance validation

### 3. Ansible Control Node
- **Target Node:** prox-two (fixed)
- **VM ID Series:** 200-series
- **CPU:** 4 cores
- **RAM:** 8 GB
- **Disk:** 50 GB
- **Static IP:** 10.110.10.8
- **Use Case:** Infrastructure orchestration and configuration management

### 4. Custom Server
- Choose your own Proxmox node, CPU, RAM, disk, and IP
- VM ID series automatically matches the target node

---

## SSH Key Management

The script generates two SSH keypairs:

### User Private Key
- **Location:** `keys/user_private_key`
- **Purpose:** Access any provisioned VM via SSH from your local machine using PuTTY
- **Action:** After the VM is built and tested, move or delete this file from the script folder for security

### Ansible Private Key
- **Location:** Generated on the Ansible control node only (never saved locally)
- **Purpose:** Allows Ansible to manage other VMs remotely
- **Security:** Stored in an obfuscated path on the Ansible server, not in obvious SSH locations

### Usage with PuTTY
1. Save the generated `user_private_key` to a secure location on your Windows machine
2. Open PuTTYgen and load `user_private_key`
3. Save as `.ppk` format
4. Use the `.ppk` file in PuTTY's SSH authentication settings
5. Connect to the VM at its static IP (e.g., 10.110.10.6 for production)

---

## Network Configuration

All VMs are configured with:
- **Subnet:** 10.110.10.0/24
- **Gateway:** 10.0.110.1
- **Primary DNS:** 10.0.110.1
- **Secondary DNS:** 8.8.4.4
- **IPv6:** Disabled

Static IPs are assigned based on server type:
- Production: 10.110.10.6
- NFT Test: 10.110.10.7
- Ansible Control: 10.110.10.8

---

## Storage Configuration

All VMs use the `zpool` shared ZFS storage pool for redundancy across the Proxmox cluster. This ensures:
- Automatic replication across nodes
- High availability (VMs can migrate between nodes if one fails)
- Shared storage for cluster failover

---

## VM Security Hardening

The script automatically configures each VM with:
- **SSH Hardening:**
- Root login disabled
- Password authentication disabled
- Public key authentication only
- Restricted to `adminops` user
- **User Configuration:**
- `adminops` user created with passwordless sudo access
- User added to Docker group for container management
- **Network Security:**
- IPv6 disabled
- Static IP configuration
- QEMU guest agent enabled for Proxmox integration
- **Key Storage:**
- Ansible private keys stored in obfuscated paths
- Authorized keys stored in randomized, non-obvious directories
- Restrictive file permissions (chmod 600/700)

---

## Logging

All provisioning activity is logged to:
```
D:\Software_Projects\ProxmoxScript\provisioning.log
```

Check this file if you encounter any errors during provisioning.

---

## Troubleshooting

### "Permission denied (publickey)" when SSH-ing to VM
- Verify you're using the correct private key (from `keys/user_private_key`)
- Ensure the key has the right permissions: `chmod 600 user_private_key`
- Check that the VM's static IP is reachable from your local network
- Verify the `adminops` user was created (check Proxmox console)

### "Remote origin already exists" when running git commands
- Skip the `git remote add` command if the repo already exists
- Just run: `git add -A && git commit -m "..." && git push`

### SSH key generation fails
- Ensure OpenSSL is installed on your system
- Check that the `keys/` directory has write permissions
- Verify you're running the script from the correct folder

### VM creation fails on Proxmox
- Verify SSH access to the target Proxmox node works
- Check that `PROX_SSH_KEY` is set to the correct path
- Ensure the target node has available resources (CPU, RAM, disk space)
- Check `provisioning.log` for detailed error messages

---

## Next Steps

After provisioning:

1. **Connect to the VM** using your `user_private_key` and PuTTY
2. **Verify static IP** is configured: `ip addr show`
3. **Test Docker** (if applicable): `docker ps`
4. **Set up Tailscale** (via Ansible playbooks) for secure remote access
5. **Configure firewall rules** in front of production server
6. **Run Ansible playbooks** for application-specific hardening and deployment

---

## Files in This Repository

- `provision-vm.sh` — Main provisioning script
- `README.md` — This file
- `.gitignore` — Excludes SSH keys and logs from Git

---

## Support

For issues or questions, refer to the logs in `provisioning.log` or review the inline comments in `provision-vm.sh`