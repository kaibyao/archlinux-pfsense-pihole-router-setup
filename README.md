# Arch Linux with pfSense and `pihole`

Finally got my custom router up and running and figured it would be worth the time to document the general steps taken to make sure that I/others can do this quickly if needed.

## Equipment

**Need:**

- A pc capable of running Arch Linux.
- 2+ Network Interface cards (this makes things easier, though you can do it with 1). I used the HP NC365T, which is a rebranded Intel i340 4-port that I got used for \$20.

## Install Software

### Install Arch Linux

Follow the installation guide in the Arch wiki. Don't forget:

- set timezone.
- install graphics drivers
- set up post-update scripts to rebuild kernel/grub configs

In order to connect the Intel i340T / 82580 NIC to the internet correctly, I had to install `ethtool` and run: `sudo ethtool -s name_of_nic autoneg off speed 1000 duplex full` for each port.

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
# --now is optional for if you want to also run a `start` command right after enabling
sudo systemctl enable --now someservice

lspci -nnk # show other information about hardware
```

**Grub default config parameters** to change:

```bash
# -enable-kvm enables libvirt & kvm
# -vga= lets you set the command line terminal resolution, 0x31B is (I think) 1280 x 1024.
GRUB_CMDLINE_LINUX_DEFAULT="quiet -enable-kvm vga=0x31B"
```

### Install KVM

Install libvirt/kvm. There's instructions online. Note that the GUI tool is not called "KVM", but "Virtual Machine Manager" (VMM).

In VMM, go to `Edit > Connection Details > Virtual Networks`. Create two virtual NICs:

1. One should have a private IP address range (both IPv4 and IPv6) and link your NIC used for the internet as a bridge (NAT mode). This allows the pfSense NIC to share the host linux’s internet connection (or WAN).
1. The other should be an internal-only virtual NIC that will be used to link pihole to pfSense as a router client.

Notable commands:

```bash
# show NICs
ip link

ethtool nic_name # more details about a specific interface
```

### Install `pihole`

Download a lightweight Debian image and install via VMM. Keep in mind that you’ll probably have to move the image file into `/var/lib/libvirt/images/` or else you might have permission issues.

Name the image `pihole` (in Virtual Machine > Overview).

- Enable at least 512mb to the VM.
- Do not enable the "Install webserver" (apache) in the installation wizard, as `pihole' ships with its own.
- The only NIC configured should be the virtual NIC sharing your internet connection (we’ll change this later). Device model `virtio` (since this isn’t FreeBSD).

Install pi-hole. Check the website for the command to run. Jot down the login password.

Shut down the VM, and change the configured NIC to the internal-facing virtual NIC.

### Other

Download pfSense image but don’t install it yet.

## Move hardware

Move your box next to the cable modem and hook it up. Then proceed as follows.

### Install pfSense

#### Preparation

Install the image via VMM. Name the image `pfsense` (in Virtual Machine > Overview).

During the initial VM creation, set up NICs as follows:

- The first NIC listed in the virtual hardware details should be the first virtual network we created earlier to connect to the internet/your cable modem. Device model: e1000/e1000e.

- The next (few) NICs should match the ports available on your other NICs that you want to use to connect your other devices on the LAN. Set Network Source to those NIC ports, passthrough mode. Also set Device Model to e1000/e1000e. As I understand it, `passthrough` means that your host OS (Arch) is giving full control of that NIC to the VM when it runs. Since we aren’t using those NICs for anything other than routing, this is fine, and is probably better performance.

- The last NIC should be the internal-facing virtual that we created, so that pihole can connect to the pfSense. Device model e1000.

_NOTE_: `virtio` drivers are buggy in FreeBSD (the OS that pfSense runs on), apparently. So never use the `virtio` drivers on this box; use `e1000` or `e1000e` instead.

#### Running the install

Use all default settings. This is important. People online have reported that not using default settings during installation can cause clients to not connect to the internet.

After pfSense is installed and configured, log into the web GUI (admin/pfsense). Again, run through the initial setup wizard using default settings (set desired admin password, though).

## Configure software

### Configure pfSense

Under "General Settings":

- Set DNS to Cloudflare/Google/whatever.
- Check: "Do not use the DNS Forwarder/DNS Resolver as a DNS server for the firewall"

Enable all interfaces. Optional: Rename all LAN + OPT interfaces into LAN1, LAN2, LANn, etc.

Create a bridge that contains all the LAN interfaces + the virtual network to the host (the one that matches the `default` virtual network). This bridge should have a static IP address of the actual router IP address that you want your devices to connect to.

Set firewall rules. Each interface (including bridge) should have an "Allow all" rule. Make sure to edit the LAN interface’s rules so that they are also "Allow all" (one of my selection boxes was not set to `any` when it should have been and this caused several hours of debugging for me).

### Configure pihole

After logging into the VM as root, check that you can `ping archlinux.org` and `wget archlinux.org` (to make sure you're connected to the internet via the virtual NIC connection to the pfsense vm).

Update the Pi-Hole admin password via `pihole -a -p`.

In the GUI, under settings > DNS, uncheck all the boxes. Then in the "custom address 1" field, add the IP Address for your router (the Network Bridge’s IP address).

Check the box for "Use Conditional Forwarding" and set your router address + domain name (domain name can be found in pfSense general settings page).

### Configure pfSense (again)

Under Diagnostics > DHCP Leases, add static IP addresses to pihole.

Under DHCP Settings, enable DHCP for the network bridge that you created.

- Set the IP Address range from .50 to .254.
- Set the DNS to the pihole’s static IP.

Connect a laptop via wired to all of the NIC ports on your new router and make sure that you are able to:

1. Access the router + pihole via their IP addresses.
2. Access the internet.

Disable the DHCP Server for LAN. You don't need it anymore.

### Configure Arch Linux

In Gnome’s system settings GUI, configure each NIC port used for the LAN so that IpV4 and V6 are disabled.

Add the following startup scripts so that both pfsense and pihole will start on startup. pfsense will load first, and then pihole will load afterwards (pihole doesn't connect to pfsense correctly if they both autostart at the same time).

```bash
sudo cp start-router-vms.sh /usr/bin
sudo chmod 755 /usr/bin/start-router-vms.sh
sudo cp start-router-vms.service /etc/systemd/system/
sudo systemctl enable --now start-router-vms.service
```
