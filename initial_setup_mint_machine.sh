#!/usr/bin/env bash
#------------------------------------------------------------------------------
# setup-network.sh — install/enable SSH, add public key, and optionally configure
#                   static IP on Linux Mint
# Usage: sudo ./setup-network.sh
#------------------------------------------------------------------------------

set -Eeuo pipefail
IFS=$'\n\t'

#------------------------------------------------------------------------------
# Error trapping: print failing line and command
#------------------------------------------------------------------------------
error_handler() {
  local lineno=$1 cmd=$2
  printf '[ERROR] Script failed at line %d: %s\n' "${lineno}" "${cmd}" >&2
  exit 1
}
trap 'error_handler ${LINENO} "${BASH_COMMAND}"' ERR

### Configuration Variables (override via env if desired) ###
readonly SSH_PORT="${SSH_PORT:-22}"
# default interface if not set in env or by prompt
INTERFACE="${INTERFACE:-wlp3s0}"
readonly DEFAULT_FIXED_IP="${FIXED_IP:-192.168.1.210/24}"
readonly GATEWAY="${GATEWAY:-192.168.1.1}"
readonly DNS_SERVERS="${DNS_SERVERS:-8.8.8.8,8.8.4.4}"
readonly SSH_PUB_KEY="${SSH_PUB_KEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDkHuZf/8XF6feS+fOHRQeVN/Q3thJFdIDt/UXgQQdkG astrolab_admin}"
readonly SSH_USER="${SSH_USER:-bgi}"

### Logging helpers #########################################
log_info()  { printf '[INFO]  %s\n' "$*"; }
die()       { printf '[ERROR] %s\n' "$*' >&2; exit 1; }

### Ensure script is run as root ############################
check_root() {
  if (( EUID != 0 )); then
    die "Must be run as root (sudo)."
  fi
}

### Prompt for the network interface ########################
prompt_interface() {
  read -r -p "Enter network interface to configure [${INTERFACE}]: " iface
  if [[ -n "$iface" ]]; then
    INTERFACE="$iface"
  fi
  log_info "Using interface: ${INTERFACE}"
}

### Prompt for passwords #####################################
prompt_set_passwords() {
  local user="${SUDO_USER:-$(whoami)}"
  log_info "Set password for user '${user}':"
  passwd "${user}"
  log_info "Set password for root:"
  passwd root
}

### Prompt and (optionally) configure static IP #############
prompt_and_configure_static_ip() {
  read -r -p "Configure static IP on ${INTERFACE}? [y/N] " response
  if [[ "${response}" =~ ^[Yy]$ ]]; then
    local addr mask
    mask="${DEFAULT_FIXED_IP#*/}"         # e.g. “24”
    read -r -p "Enter IP address (no mask, e.g. 192.168.1.210): " addr
    FIXED_IP="${addr}/${mask}"
    configure_static_ip
  else
    log_info "Skipping static IP configuration."
  fi
}

### Grant passwordless sudo to SSH_USER ####################################
configure_passwordless_sudo() {
  log_info "Configuring passwordless sudo for ${SSH_USER}…"
  cat > "/etc/sudoers.d/${SSH_USER}" <<EOF
${SSH_USER} ALL=(ALL) NOPASSWD:ALL
EOF
  chmod 0440 "/etc/sudoers.d/${SSH_USER}"
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
  systemctl enable NetworkManager
  systemctl start  NetworkManager
}

### Add provided public SSH key to the specified user  ########
add_ssh_key() {
  if [[ -z "${SSH_PUB_KEY}" ]]; then
    log_info "No public SSH key provided; skipping."
    return
  fi
  if ! id "${SSH_USER}" &>/dev/null; then
    die "User '${SSH_USER}' does not exist."
  fi
  local ssh_dir
  ssh_dir=$(eval echo "~${SSH_USER}/.ssh")

  log_info "Creating ${ssh_dir} and installing key…"
  mkdir -p "${ssh_dir}"
  chmod 700 "${ssh_dir}"
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
    log_info "UFW not installed; skipping firewall changes."
  fi
}

### Configure static IP via NetworkManager ####################
configure_static_ip() {
  log_info "Finding NM connection for ${INTERFACE}…"
  local conn
  conn=$(nmcli -t -f NAME,DEVICE con show --active \
    | grep ":${INTERFACE}$" \
    | cut -d: -f1) \
    || die "No active NM connection for ${INTERFACE}."
  log_info "Setting static IP ${FIXED_IP}, gateway ${GATEWAY}, DNS ${DNS_SERVERS}…"
  nmcli con mod "${conn}" \
    ipv4.addresses "${FIXED_IP}" \
    ipv4.gateway   "${GATEWAY}" \
    ipv4.dns       "${DNS_SERVERS}" \
    ipv4.method    manual
  nmcli con down "${conn}"
  nmcli con up   "${conn}"
}

### Restart NetworkManager service ############################
restart_network_manager() {
  log_info "Restarting NetworkManager…"
  systemctl restart NetworkManager
}

### Main ######################################################
main() {
  check_root
  prompt_interface
  prompt_set_passwords
  prompt_and_configure_static_ip
  configure_passwordless_sudo
  install_and_enable_ssh
  install_and_enable_nm
  add_ssh_key
  open_ssh_port
  restart_network_manager
  log_info "All done."
}

main "$@"
