#!/bin/sh
# BootToTheWeb init script
# Copyright (c) 2015 Joshua Higgins
# Released under the terms of the GNU GPL v3

end_early ()
{
	echo ""
	echo "The system cannot start."
	read -p "Press [Enter] key to reboot"
	reboot
}

check_download ()
{
	wget $1 -O $2
	if [ $? -ne 0 ]; then
		echo "There was an error downloading the file $1"
		end_early
	fi
}

# try and get server from /proc/cmdline
# otherwise use default source
defaultsource="http://platformctrl.com"
for x in $(cat /proc/cmdline || echo server=$defaultsource)
do
        case $x in
                server=*)
                server="${x//server=}"
                ;;
        esac
done

if [ "$server" = "" ]; then
	echo "No source found in /proc/cmdline"
	server=$defaultsource
fi

# download the configuration file
echo "Downloading configuration from $server"

devices=$(ls /sys/class/net/ | grep -v lo)

for device in $devices "default"; do
	if [ "$device" = "default" ]; then
		echo "Getting default config..."
		address="default"
	else
		echo "Device $device has MAC $address, looking for config..."
		address=`cat /sys/class/net/$device/address`
	fi
	wget $server/$address -O /tmp/config
	if [ $? -eq 0 ]; then
		break
	fi
done

# parse values and download payload
b_server="`cat /tmp/config | grep SERVER | cut -d' ' -f2-`"
b_kernel="`cat /tmp/config | grep KERNEL | cut -d' ' -f2-`"
b_initrd="`cat /tmp/config | grep INITRD | cut -d' ' -f2-`"
b_append="`cat /tmp/config | grep APPEND | cut -d' ' -f2-`"

if [ "$b_server" = "" ]; then
	b_server=$server
fi
if [ "$b_kernel" = "" ]; then
	echo "The configuration source did not provide a kernel"
	end_early
else
	echo "Downloading kernel..."
	check_download $b_server/$b_kernel -O /tmp/kernel
fi
if [ "$b_initrd" = "" ]; then
	echo "The configuration source did not provide a initrd"
else
	echo "Downloading initrd..."
	check_download $b_server/$b_initrd -O /tmp/initrd
fi
if [ "$b_append" = "" ]; then
	echo "The configuration source did not provide any append arguments"
fi

# do the kexec
echo "Preparing to kexec the new kernel..."
if [ "$b_initrd" = "" ]; then
	kexec -l /tmp/kernel --command-line="$b_append" || end_early
else
	kexec -l /tmp/kernel --command-line="$b_append" --initrd=/tmp/initrd || end_early
fi

kexec -e

# this should be the end, otherwise...

echo "The new kernel failed to load."
end_early