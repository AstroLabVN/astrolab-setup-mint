#!/usr/bin/env bash
#------------------------------------------------------------------------------
# setup-network.sh — install/enable SSH, add public key, and configure static IP on Linux Mint
# Usage: sudo ./setup-network.sh
#------------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

### Configuration Variables (override via env if desired) ###
SSH_PORT="${SSH_PORT:-22}"
INTERFACE="${INTERFACE:-wlp3s0}"
FIXED_IP="${FIXED_IP:-192.168.1.211/24}"
GATEWAY="${GATEWAY:-192.168.1.1}"
DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
# Specify user to receive the SSH key, and the public key itself
SSH_USER="${SSH_USER:-bgi}"
SSH_PUB_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDkHuZf/8XF6feS+fOHRQeVN/Q3thJFdIDt/UXgQQdkG astrolab_admin"

### Logging helpers #########################################
log_info()  { printf "[INFO]  %s\n" "$*"; }
log_error() { printf "[ERROR] %s\n" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

### Ensure script is run as root ############################
check_root() {
  if (( EUID != 0 )); then
    die "Must be run as root (sudo)."
  fi
}

### Install & start SSH server ################################
install_and_enable_ssh() {
  if ! command -v sshd &>/dev/null; then
    log_info "Installing OpenSSH server…"
    apt update
    apt install -y openssh-server
  else
    log_info "OpenSSH already installed."
  fi

  log_info "Enabling and starting ssh service…"
  systemctl enable ssh
  systemctl start  ssh
}

### Install & ensure NetworkManager ###########################
install_and_enable_nm() {
  if ! command -v nmcli &>/dev/null; then
    log_info "Installing NetworkManager…"
    apt update
    apt install -y --no-install-recommends network-manager
  else
    log_info "NetworkManager already installed."
  fi

  log_info "Enabling and starting NetworkManager service…"
  systemctl enable NetworkManager
  systemctl start  NetworkManager
}

### Add provided public SSH key to the specified user  ########
add_ssh_key() {
  if [[ -z "${SSH_PUB_KEY}" ]]; then
    log_info "No public SSH key provided; skipping key setup."
    return
  fi

  if ! id "${SSH_USER}" &>/dev/null; then
    die "User '${SSH_USER}' does not exist."
  fi

  local ssh_dir
  ssh_dir=$(eval echo "~${SSH_USER}/.ssh")

  log_info "Creating .ssh directory for ${SSH_USER}…"
  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"

  log_info "Adding public key to ${ssh_dir}/authorized_keys…"
  printf '%s\n' "${SSH_PUB_KEY}" > "${ssh_dir}/authorized_keys"
  chmod 600 "${ssh_dir}/authorized_keys"
  chown -R "${SSH_USER}:${SSH_USER}" "${ssh_dir}"
}

### Open SSH port in UFW (if present) ########################
open_ssh_port() {
  if command -v ufw &>/dev/null; then
    log_info "Allowing SSH port ${SSH_PORT} in UFW…"
    ufw allow "${SSH_PORT}/tcp"
    ufw reload
  else
    log_info "UFW not installed; skipping firewall configuration."
  fi
}

### Configure static IP via NetworkManager ####################
configure_static_ip() {
  log_info "Locating connection for interface '${INTERFACE}'…"
  local conn
  conn=$(nmcli -t -f NAME,DEVICE con show --active \
      | grep ":${INTERFACE}$" \
      | cut -d: -f1) \
    || die "No active NM connection found for ${INTERFACE}."

  log_info "Modifying NM connection '${conn}' to use static IP…"
  nmcli con mod "${conn}" \
    ipv4.addresses "${FIXED_IP}" \
    ipv4.gateway   "${GATEWAY}" \
    ipv4.dns       "${DNS_SERVERS}" \
    ipv4.method    manual

  log_info "Bringing connection '${conn}' down/up…"
  nmcli con down "${conn}"
  nmcli con up   "${conn}"
}

### Restart NetworkManager service ############################
restart_network_manager() {
  log_info "Restarting NetworkManager service…"
  systemctl restart NetworkManager
}

### Main ######################################################
main() {
  check_root
  install_and_enable_ssh
  install_and_enable_nm
  add_ssh_key
  open_ssh_port
  configure_static_ip
  restart_network_manager
  log_info "All done!"
}

main "$@"
