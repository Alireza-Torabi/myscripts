#!/bin/bash

# Function to generate SSH key with password
generate_ssh_key() {
    read -p "Enter the desired hostname: " hostname
    read -s -p "Enter a password for the private key: " key_password
    echo

    echo "Generating SSH key for $hostname..."
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/$hostname -N "$key_password"
}

# Function to import SSH public key to remote server
import_public_key() {
    read -p "Enter the remote server IP address: " remote_ip
    read -p "Enter the remote server username: " remote_user
    read -s -p "Enter the password for $remote_user@$remote_ip: " remote_password
    echo

    echo "Copying SSH public key to the remote server..."
    sshpass -p "$remote_password" ssh-copy-id -i ~/.ssh/$hostname.pub "$remote_user@$remote_ip"
}

# Main script
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y ssh-keygen sshpass

generate_ssh_key
import_public_key

echo "SSH key generation and import to $remote_ip is completed for $hostname."
