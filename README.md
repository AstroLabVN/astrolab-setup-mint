## Overview

This script automates the initial setup of a network connection and SSH access on a fresh Debian-based Linux system, such as Ubuntu or Linux Mint. It is designed to be run with `sudo` and performs essential setup tasks idempotently, meaning it can be run multiple times without causing issues.

The script will:
- Install required packages.
- Set up a user with SSH key access and passwordless `sudo`.
- Configure the firewall.
- Optionally set a static IP address for a chosen network interface.


## Features

- **Package Installation**: Ensures `openssh-server` and `network-manager` are installed.
- **Service Management**: Enables and starts the `ssh` and `NetworkManager` services.
- **User Setup**: Prompts to set passwords for the `root` user and the user running the script.
- **Passwordless Sudo**: Grants the target user passwordless `sudo` privileges by adding a configuration file to `/etc/sudoers.d/`.
- **SSH Key Installation**: Adds a specified public SSH key to the user's `~/.ssh/authorized_keys` file for secure, passwordless login.
- **Firewall Configuration**: Automatically detects if `ufw` (Uncomplicated Firewall) is active and, if so, adds a rule to allow SSH connections (port 22).
- **Static IP Configuration**: Interactively prompts the user to configure a static IP address, gateway, and DNS servers for a specified network interface using `nmcli`.


## Prerequisites

- A Debian-based Linux distribution (e.g., Ubuntu, Linux Mint).
- `sudo` or root access on the machine.


## Usage

1.  **Download the Script**:
Save the script as `initial_setup_debian_machine.sh` on your target machine.
```bash
curl -fsSL https://raw.githubusercontent.com/AstroLabVN/astrolab-setup-mint/refs/heads/main/initial_setup_debian_machine.sh > initial_setup_debian_machine.sh
```



2.  **Configure Variables**:
Open the script and edit the variables in the `Configuration Variables` section to match your needs. At a minimum, you **must** change `SSH_PUB_KEY` to your own public key.

Alternative, you can export them as environment variables before running the script:
```bash
export SSH_PUB_KEY="ssh-rsa AAAA..."
export INTERFACE="eth0"
```

## Prerequisites

- A Debian-based Linux distribution (e.g., Ubuntu, Linux Mint).
- `sudo` or root access on the machine.


3.  **Make the Script Executable**:
```bash
chmod +x initial_setup_debian_machine.sh
```

4.  **Run the Script**:
Execute the script with `sudo`. It will prompt you for input during execution.
```bash
sudo bash ./initial_setup_debian_machine.sh
```

***

```
## Configuration

The script's behavior can be customized by editing the variables at the top of the file or by setting them as environment variables.

| Variable           | Default Value                                   | Description                                                                                                                              |
| ------------------ | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `SSH_USER`         | `${SUDO_USER:-bgi}`                             | The user account that will receive the SSH key and passwordless `sudo` rights. Defaults to the user invoking `sudo`.                  |
| `SSH_PUB_KEY`      | `"ssh-ed25519 AAA... your_key_comment"`         | **IMPORTANT**: The public SSH key to install for `SSH_USER`. You must replace the default placeholder with your actual public key.       |
| `INTERFACE`        | `wlp3s0`                                        | The default network interface to configure. The script will list available interfaces and prompt you to confirm or change this.      |
| `DEFAULT_FIXED_IP` | `192.168.1.210/24`                              | The default static IP address and subnet mask (in CIDR format) to assign if you opt for static IP configuration.                     |
| `GATEWAY`          | `192.168.1.1`                                   | The network gateway address to use with the static IP.                                                                                   |
| `DNS_SERVERS`      | `8.8.8.8,8.8.4.4`                               | A comma-separated list of DNS servers to use with the static IP.                                                                         |
```

## How It Works

The script executes its tasks in a specific order to ensure stability:

1.  **System Preparation**: It first installs all necessary packages and ensures critical services (`ssh`, `NetworkManager`) are running.
2.  **User & Security Setup**: It then configures user passwords, passwordless `sudo`, installs the SSH key, and opens the firewall. These actions do not depend on network state.
3.  **Network Configuration**: Finally, it performs the network configuration. This is done last because changing the IP address can cause a temporary network disconnection.

This logical flow minimizes the risk of the script failing midway through due to a loss of network connectivity.
