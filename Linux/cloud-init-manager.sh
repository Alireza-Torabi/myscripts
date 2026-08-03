#!/usr/bin/env bash

set -e

BACKUP_DIR="/root/cloud-init-backup-$(date +%Y%m%d-%H%M%S)"
LOG_FILE="/var/log/cloud-init-manager.log"

require_root()
{
    if [ "$EUID" -ne 0 ]; then
        echo "Please run as root"
        exit 1
    fi
}

check_os()
{
    if [ -f /etc/os-release ]; then
        source /etc/os-release

        if [[ "$ID" != "ubuntu" ]]; then
            echo "This script supports Ubuntu only"
            exit 1
        fi

        echo "Detected Ubuntu $VERSION_ID"
    fi
}


backup_config()
{
    echo "[+] Creating backup..."

    mkdir -p "$BACKUP_DIR"

    cp -a /etc/cloud "$BACKUP_DIR/" 2>/dev/null || true
    cp -a /var/lib/cloud "$BACKUP_DIR/" 2>/dev/null || true
    cp -a /etc/netplan "$BACKUP_DIR/" 2>/dev/null || true

    systemctl list-unit-files | grep cloud \
        > "$BACKUP_DIR/cloud-services.txt" || true

    dpkg -l | grep cloud \
        > "$BACKUP_DIR/cloud-packages.txt" || true


    echo "$BACKUP_DIR" > /root/cloud-init-last-backup

    echo "[+] Backup completed:"
    echo "$BACKUP_DIR"
}


disable_network()
{
    echo "[+] Disabling cloud-init network management"

    mkdir -p /etc/cloud/cloud.cfg.d

    cat > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg <<EOF
network:
  config: disabled
EOF


    echo "[+] Network configuration disabled"
}


disable_all()
{
    echo "[+] Disabling cloud-init services"

    touch /etc/cloud/cloud-init.disabled


    systemctl disable cloud-init.service || true
    systemctl disable cloud-init-local.service || true
    systemctl disable cloud-config.service || true
    systemctl disable cloud-final.service || true


    systemctl stop cloud-init.service || true
    systemctl stop cloud-init-local.service || true
    systemctl stop cloud-config.service || true
    systemctl stop cloud-final.service || true


    echo "[+] cloud-init disabled"
}


purge_cloudinit()
{
    echo "[!] Removing cloud-init completely"

    apt remove --purge cloud-init -y

    rm -rf /etc/cloud
    rm -rf /var/lib/cloud

    echo "[+] Purge completed"
}


restore()
{

    if [ ! -f /root/cloud-init-last-backup ]; then
        echo "No backup found"
        exit 1
    fi


    BACKUP=$(cat /root/cloud-init-last-backup)

    echo "[+] Restoring from:"
    echo "$BACKUP"


    rm -rf /etc/cloud
    rm -rf /var/lib/cloud
    rm -rf /etc/netplan


    cp -a "$BACKUP/cloud" /etc/cloud 2>/dev/null || true
    cp -a "$BACKUP/cloud" /var/lib/cloud 2>/dev/null || true
    cp -a "$BACKUP/netplan" /etc/netplan 2>/dev/null || true


    touch /etc/cloud/cloud-init.disabled || true

    echo "[+] Restore finished"
}


menu()
{

clear

echo "
Cloud-init Manager

1) VMware / Proxmox / Bare Metal
   (Disable cloud-init network)

2) Kubernetes Node
   (Disable cloud-init network)

3) Cloud Provider
   (Keep cloud-init)

4) Disable completely

5) Purge cloud-init

6) Restore previous backup

0) Exit

"


read -p "Select option: " OPTION


case $OPTION in

1)
backup_config
disable_network
;;

2)
backup_config
disable_network
;;

3)
echo "No changes applied"
;;

4)
backup_config
disable_all
;;

5)
backup_config
purge_cloudinit
;;

6)
restore
;;

0)
exit
;;

*)
echo "Invalid option"
;;

esac

}


require_root
check_os
menu
