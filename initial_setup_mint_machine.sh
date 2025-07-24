#!/usr/bin/env bash
#------------------------------------------------------------------------------
# setup-network.sh — Install/enable SSH, add a public key, and optionally
#                    configure a static IP on a Debian-based system like
#                    Linux Mint or Ubuntu.
#
# Usage:
#   1. Review and edit the "Configuration Variables" section below.
#   2. Make the script executable: chmod +x setup-network.sh
#   3. Run with sudo: sudo ./setup-network.sh
#
#------------------------------------------------------------------------------

# Exit immediately if a command exits with a non-zero status, if an unset
# variable is used, and to propagate exit status through pipes.
set -Eeuo pipefail
# Set the Internal Field Separator to handle spaces in filenames gracefully.
IFS=$'\n\t'

#------------------------------------------------------------------------------
# Configuration Variables
#
# You can override these by setting environment variables before running the
# script, e.g., `export INTERFACE=eth0`
#------------------------------------------------------------------------------
# The user to whom the SSH key and passwordless sudo will be applied.
# Defaults to the user who invoked sudo, or 'bgi' as a fallback.
readonly SSH_USER="${SUDO_USER:-bgi}"

# The public key to add to the user's authorized_keys file.
# IMPORTANT: Replace this with your actual public key.
readonly SSH_PUB_KEY="${SSH_PUB_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDkHuZf/8XF6feS+fOHRQeVN/Q3thJFdIDt/UXgQQdkG your_key_comment}"

# Network settings for the static IP configuration.
# The default network interface to configure. The script will prompt for this.
INTERFACE="${INTERFACE:-wlp3s0}"
readonly DEFAULT_FIXED_IP="${FIXED_IP:-192.168.1.210/24}"
readonly GATEWAY="${GATEWAY:-192.168.1.1}"
readonly DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"

#------------------------------------------------------------------------------
# Helper Functions
#------------------------------------------------------------------------------

# --- Logging helpers ---
# Prefixes messages with [INFO] or [ERROR] for clarity.
log_info() { printf "\n[INFO] %s\n" "$*"; }
log_warn() { printf "\n[WARN] %s\n" "$*"; }
die() {
  printf "\n[ERROR] %s\n" "$*" >&2
  exit 1
}

# --- Error trapping ---
# Captures the line number and command of a script failure.
error_handler() {
  local lineno=$1 cmd=$2
  die "Script failed at line %d with command: %s" "${lineno}" "${cmd}"
}
trap 'error_handler ${LINENO} "${BASH_COMMAND}"' ERR

#------------------------------------------------------------------------------
# Script Functions
#------------------------------------------------------------------------------

# Ensures the script is executed with root privileges.
check_root() {
  if ((EUID != 0)); then
    die "This script must be run as root. Please use 'sudo'."
  fi
}

# Installs necessary packages if they are not already present.
install_dependencies() {
  log_info "Updating package lists..."
  apt-get update

  log_info "Ensuring openssh-server and network-manager are installed..."
  # Using a single install command is more efficient.
  apt-get install -y openssh-server network-manager
}

# Enables and starts essential services.
enable_services() {
  log_info "Enabling and starting ssh and NetworkManager services..."
  systemctl enable ssh
  systemctl start ssh
  systemctl enable NetworkManager
  systemctl start NetworkManager
}

# Prompts to set passwords for the target user and root.
prompt_set_passwords() {
  log_info "You will be prompted to set passwords."
  printf "Set password for user '%s':\n" "${SSH_USER}"
  passwd "${SSH_USER}"
  printf "Set password for 'root' user:\n"
  passwd root
}

# Grants passwordless sudo privileges to the specified user.
configure_passwordless_sudo() {
  log_info "Configuring passwordless sudo for '${SSH_USER}'..."
  local sudoer_file="/etc/sudoers.d/90-${SSH_USER}-nopasswd"
  echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" >"${sudoer_file}"
  chmod 0440 "${sudoer_file}"
  log_info "Passwordless sudo configured in ${sudoer_file}"
}

# Adds the public SSH key to the specified user's account.
add_ssh_key() {
  if [[ -z "${SSH_PUB_KEY}" ]]; then
    log_warn "SSH_PUB_KEY variable is empty. Skipping key installation."
    return
  fi

  # Safely get the user's home directory.
  local home_dir
  home_dir=$(getent passwd "${SSH_USER}" | cut -d: -f6)
  if [[ -z "${home_dir}" ]]; then
    die "Could not find home directory for user '${SSH_USER}'. Does the user exist?"
  fi

  local ssh_dir="${home_dir}/.ssh"
  local key_file="${ssh_dir}/authorized_keys"

  log_info "Installing SSH public key to ${key_file}..."
  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"
  echo "${SSH_PUB_KEY}" >"${key_file}"
  chmod 600 "${key_file}"
  chown -R "${SSH_USER}:${SSH_USER}" "${ssh_dir}"
  log_info "SSH key successfully installed."
}

# Opens the standard SSH port in UFW if the firewall is active.
open_ssh_port_in_firewall() {
  if command -v ufw &>/dev/null && ufw status | grep -q 'Status: active'; then
    log_info "UFW is active. Allowing SSH connections on port 22..."
    ufw allow ssh
    ufw reload
  else
    log_info "UFW not found or is inactive. Skipping firewall configuration."
  fi
}

# Configures a static IP address using NetworkManager's command-line tool.
configure_static_ip() {
  local conn_name fixed_ip
  log_info "Attempting to find active NetworkManager connection for '${INTERFACE}'..."

  # This command is more robust for finding the connection name.
  conn_name=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":${INTERFACE}$" | cut -d: -f1)

  if [[ -z "$conn_name" ]]; then
    die "No active NetworkManager connection found for interface '${INTERFACE}'. Please check the interface name."
  fi

  log_info "Found active connection: '${conn_name}'"

  # Prompt for the IP address, using the default as a suggestion.
  read -r -p "Enter static IP address with mask [${DEFAULT_FIXED_IP}]: " ip_input
  fixed_ip="${ip_input:-$DEFAULT_FIXED_IP}"

  log_warn "Applying static IP. This will temporarily disconnect the network!"
  log_info "Configuring '${conn_name}' with IP: ${fixed_ip}, Gateway: ${GATEWAY}, DNS: ${DNS_SERVERS}"

  nmcli connection modify "${conn_name}" \
    ipv4.method manual \
    ipv4.addresses "${fixed_ip}" \
    ipv4.gateway "${GATEWAY}" \
    ipv4.dns "${DNS_SERVERS}"

  log_info "Applying new network configuration..."
  # Re-apply the connection settings. This is safer than restarting the whole service.
  nmcli connection up "${conn_name}"
  log_info "Static IP configuration applied."
}

# Main function to orchestrate the setup process.
main() {
  check_root

  # --- System Preparation ---
  install_dependencies
  enable_services

  # --- User and Security Configuration ---
  prompt_set_passwords
  configure_passwordless_sudo
  add_ssh_key
  open_ssh_port_in_firewall

  # --- Network Configuration (done last) ---
  log_info "Available network interfaces:"
  # List interfaces to help the user choose.
  nmcli -t -f DEVICE,TYPE device status | grep -v '^lo:'
  
  read -r -p "Enter the network interface to configure [${INTERFACE}]: " iface_input
  # Only update INTERFACE if the user provided input.
  if [[ -n "$iface_input" ]]; then
    INTERFACE="$iface_input"
  fi
  log_info "Using interface: ${INTERFACE}"

  read -r -p "Do you want to configure a static IP on '${INTERFACE}'? [y/N] " response
  if [[ "${response}" =~ ^[Yy]$ ]]; then
    configure_static_ip
  else
    log_info "Skipping static IP configuration. The system will use DHCP."
  fi

  log_info "--------------------------------------------------"
  log_info "Setup complete!"
  log_info "Current IP address for '${INTERFACE}':"
  ip addr show "${INTERFACE}" | grep "inet " | awk '{print $2}'
  log_info "--------------------------------------------------"
}

# Execute the main function with all script arguments.
main "$@"
