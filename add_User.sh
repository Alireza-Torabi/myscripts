#!/bin/bash

# Check if running as root
if [[ $EUID -ne 0 ]]; then
  echo "Please run as root."
  exit 1
fi

# Detect distro
if [ -f /etc/os-release ]; then
  . /etc/os-release
  DISTRO=$ID
else
  echo "Cannot detect Linux distribution."
  exit 1
fi

echo "Detected distro: $DISTRO"

# Ask for username
read -p "Enter the new username: " username

# Check if user exists
if id "$username" &>/dev/null; then
  echo "User $username already exists."
  exit 1
fi

# Ask if user needs root privileges
while true; do
  read -p "Should the user have root (sudo) privileges? (yes/no): " yn
  case $yn in
    [Yy]* ) root_priv=true; break;;
    [Nn]* ) root_priv=false; break;;
    * ) echo "Please answer yes or no.";;
  esac
done

# Add user
useradd "$username"

# Set password
echo "Set password for $username:"
passwd "$username"

# Grant sudo/root privileges if requested
if $root_priv; then
  case "$DISTRO" in
    centos|rhel|fedora)
      # Add to wheel group
      usermod -aG wheel "$username"
      echo "Added $username to wheel group for sudo privileges."
      ;;
    ubuntu|debian)
      # Add to sudo group
      usermod -aG sudo "$username"
      echo "Added $username to sudo group for sudo privileges."
      ;;
    *)
      echo "Warning: Unknown distro. Please manually add user to sudoers if needed."
      ;;
  esac
fi

echo "User $username created successfully."

# Reminder
echo "You can switch to the user with: su - $username"
if $root_priv; then
  echo "Test sudo with: sudo whoami"
fi
