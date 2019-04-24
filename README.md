# Arch Linux with pfSense and `pihole`

Finally got my custom router up and running and figured it would be worth the time to document the general steps taken to make sure that I/others can do this quickly if needed.

## Equipment

**Need:**

- A pc capable of running Arch Linux.
- 2+ Network Interface cards (this makes things easier, though you can do it with 1).

## Install Software

### Install Arch Linux

Follow the installation guide in the Arch wiki. Don't forget:

- set timezone.
- install graphics drivers
- set up post-update scripts to rebuild kernel/grub configs

There are additional steps that need to be taken to enable kvm/libvirt/qemu (mostly around adding kernel flags in the grub config, though kvm recommends changing the user and group settings).

**Notable shell commands:**

```bash
# rebuild Linux kernel config
mkinitcpio -p linux

# edit grub default config
sudo vim /etc/default/grub

# rebuild grub config that is actually used during boot
grub-mkconfig -o /boot/grub/grub.cfg

# enable system services
sudo systemctl enable --now someservice # --now is optional for if you want to also run a `start` command right after enabling
```

**Grub default config parameters** to change:

```bash
# -enable-kvm enables libvirt & kvm
# -vga= lets you set the command line terminal resolution, 0x31B is (I think) 1280 x 1024.
GRUB_CMDLINE_LINUX_DEFAULT="quiet -enable-kvm vga=0x31B"
```

### Install KVM

Install libvirt/kvm. There's instructions online. Note that the GUI tool is not called "KVM", but "Virtual Machine Manager" (VMM).

In VMM, go to `Edit > Connection Details > Virtual Networks`. Autostart `default` (virbr0) on boot.
Alternatively, you can do the same by running `sudo virsh net-autostart default`.

Make sure that it has started by running `sudo virsh net-start default`.

_NOTE_: This `default` network allows our VMs to share the same virtual network with each other, as well as with the host Arch Linux OS. This is how `pihole` and `pfSense` will communicate with each other.

### Install pfSense

Download pfSense and install the image via VMM. Set the LAN IP address to 192.168.10.1 (It’s only going to be used for setup, we’ll disable this later).
Name the image `pfsense` (in Virtual Machine > Overview).

In VMM, set up NICs as follows:

- The first NIC listed in the virtual hardware details should be what you use to connect to the internet/your cable modem. Set Network source to your NIC, bridge mode. Device model: e1000/e1000e.

- The next (few) NICs should match the ports available on your other NICs that you want to use to connect your other devices on the LAN. Set Network Source to those NIC ports, passthrough mode. Also set Device Model to e1000/e1000e. As I understand it, `passthrough` means that your host OS (Arch) is giving full control of that NIC to the VM when it runs. Since we aren’t using those NICs for anything other than routing, this is fine, and is probably better performance.

- The last NIC should be `Virtual network 'default': NAT` (the network we enabled). Device model e1000.

_NOTE_: `virtio` drivers are buggy in FreeBSD (the OS that pfSense runs on), apparently. So never use the `virtio` drivers on this box; use `e1000` or `e1000e` instead.

### Install `pihole`

Download a lightweight Debian image and install via VMM.
Name the image `pihole` (in Virtual Machine > Overview).

- Enable at least 512mb to the VM.
- Do not enable the "Install webserver" (apache) in the installation wizard, as `pihole' ships with its own.
- The only NIC configured should be `Virtual network 'default': NAT` (the network we enabled). Device model `virtio` (since this isn’t FreeBSD).

Install pi-hole. Check the website for the command to run. Jot down the login password.

## Configure software

### Configure pfSense

Under "General Settings":

- Set DNS to Cloudflare/Google/whatever.
- Check: "Do not use the DNS Forwarder/DNS Resolver as a DNS server for the firewall"

Enable all interfaces.

Create a bridge that contains all the LAN interfaces + the virtual network to the host (the one that matches the `default` virtual network).

- This bridge should have a static IP address of the actual router IP address that you want your devices to connect to.
- need to add stuff about the checkboxes to check.

Set firewall rules. Each interface (including bridge) should have an "Allow all" rule. Make sure to edit the LAN interface’s rules so that they are also "Allow all" (one of my selection boxes was not set to `any` when it should have been and this caused several hours of debugging for me).

### Configure pihole

Update the root password via `pihole -a -p`.

In the GUI, under settings > DNS, uncheck all the boxes. Then in the "custom address 1" field, add the IP Address for your router (the Network Bridge’s IP address).

Check the box for...

### Configure pfSense (again)

Under Diagnostics > DHCP Leases, add static IP addresses to pihole.

Under DHCP Settings, enable DHCP for the network bridge that you created.

- Set the IP Address range from .50 to .254.
- Set the DNS to the pihole’s static IP.

Connect a laptop via wired to all of the NIC ports on your new router and make sure that you are able to:

1. Access the router + pihole via their IP addresses.
2. Access the internet.

Disable the DHCP Server for LAN. You don't need it anymore.

In VMM, change the first NIC’s (the WAN NIC) mode to "Passthrough". This makes it so Arch Linux host will no longer have an internet connection when pfSense is running.

### Configure Arch Linux

In Gnome’s system settings GUI, configure each NIC port used for the LAN so that IpV4 and V6 are disabled.

Add the following startup scripts so that both pfsense and pihole will start on startup. pfsense will load first, and then pihole will load afterwards (pihole doesn't connect to pfsense correctly if they both autostart at the same time).

1. `sudo cp start-router-vms.sh /usr/bin`
1. `sudo chmod 755 /usr/bin/start-router-vms.sh`
1. `sudo cp start-router-vms.service /etc/systemd/system/`
1. `sudo systemctl enable --now start-router-vms.service`
