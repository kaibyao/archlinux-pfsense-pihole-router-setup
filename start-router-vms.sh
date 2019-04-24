#! /bin/bash

# Start pfsense
virsh start pfsense

# Wait until pfsense is up and running, note that the IP address should match your router's IP address
until ping -c1 192.168.4.1 >/dev/null 2>&1; do
    sleep 2
done

# Start pihole
virsh start pihole

# `sudo mv` this file to /usr/bin/
