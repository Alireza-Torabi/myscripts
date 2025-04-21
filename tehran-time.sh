#!/bin/bash

# Create file for Tehran time zone configuration
cd ~
sudo touch tehran-time
sudo chmod 666 tehran-time

# Add configuration
cat <<EOF | sudo tee -a tehran-time
# Zone  NAME          GMTOFF  RULES FORMAT [UNTIL]
Zone    Tehran-nodst  3:25:44 -     LMT    1916
                      3:25:44 -     TMT    1946    # Tehran Mean Time
                      3:30    -     IRST   1977 Nov
                      4:00    -     IRST   1979
                      3:30    -     IRST
EOF

# Create timezone configuration
sudo zic -d . tehran-time

# Copy configuration to system timezone folder
sudo cp Tehran-nodst /usr/share/zoneinfo/Asia/

# Backup current timezone configuration
sudo mv /etc/localtime /etc/localtime.backup

# Create symbolic link to new timezone configuration
sudo ln -s /usr/share/zoneinfo/Asia/Tehran-nodst /etc/localtime

# Remove temporary file
sudo rm tehran-time

# Prompt for NTP server address
echo "Enter NTP server address (e.g. pool.ntp.org): "
read ntp_server1
echo "Enter NTP server address (e.g. pool.ntp.org): "
read ntp_server2

# Add NTP server to timesyncd.conf
sudo sed -i "s/#NTP=/NTP=$ntp_server1/" /etc/systemd/timesyncd.conf
sudo sed -i "s/#NTP=/NTP=$ntp_server2/" /etc/systemd/timesyncd.conf

# Restart timesyncd service
sudo systemctl restart systemd-timesyncd.service
Beta
0 / 10
used queries
1
