#!/bin/bash

# Display a list of existing users
echo "List of existing users:"
awk -F: '{print $1}' /etc/passwd

# Prompt for the username to delete
read -p "Enter the username to delete: " username

# Check if the user exists
if id "$username" &>/dev/null; then
    # List and kill processes associated with the user
    echo "Killing processes associated with user '$username'"
    sudo pkill -u "$username"

    # Delete the user
    sudo deluser --remove-home "$username"
    echo "User '$username' deleted."
else
    echo "User '$username' does not exist."
fi
Beta
0 / 10
used queries
1
