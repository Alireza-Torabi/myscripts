#!/bin/bash

# Check if the script is run with root privileges
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

# Prompt for username
read -p "Enter the username: " username

# Check if the user already exists
if id "$username" &>/dev/null; then
  echo "User '$username' already exists."
  exit 1
fi

# Prompt for password (Note: This is not secure for production use)
read -s -p "Enter the password: " password
echo

# Create user with root privileges
sudo useradd -m -s /bin/bash $username
echo "$username:$password" | sudo chpasswd

# Add user to the sudo group
sudo usermod -aG sudo $username

echo "User '$username' created with root privileges."
Beta
0 / 10
used queries
1
