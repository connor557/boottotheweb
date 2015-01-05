#!/bin/sh
# BootToTheWeb init script
# Copyright (c) 2015 Joshua Higgins
# Released under the terms of the GNU GPL v3

. /etc/init.d/tc-functions

end_early ()
{
	echo ""
	echo "${WHITE}The system cannot start.${NORMAL}"
	read -p "Press [Enter] key to reboot"
	reboot
}

check_download ()
{
	wget $1 -O $2
	if [ $? -ne 0 ]; then
		echo "${RED}There was an error downloading the file ${YELLOW}$1${NORMAL}"
		end_early
	fi
}

show_menu ()
{
	# display a menu
	clear
	echo "Please select an OS to start and press <Enter> key:"
	for x in $(ls /tmp/configs); do
		echo "$x) `cat /tmp/configs/$x | grep LABEL | cut -d' ' -f2-`"
	done
	read opt
	cp /tmp/configs/$opt /tmp/config
	if [ $? -ne 0 ]; then
		show_menu
	fi
}

# begin

echo "${GREEN}BootToTheWeb ${YELLOW}version 1.0${NORMAL}"

# configure the network
echo "${BLUE}Configuring network...${NORMAL}"
udhcpc || end_early

# try and get server from /proc/cmdline
# otherwise use default source
defaultsource="http://platformctrl.com"
for x in $(cat /proc/cmdline || echo server=$defaultsource)
do
        case $x in
                server=*)
                server="${x//server=}"
                ;;
                proxy=*)
                proxy="${x//proxy=}"
                ;;
        esac
done

export http_proxy="$proxy"
export https_proxy="$proxy"

if [ "$server" = "" ]; then
	echo "${YELLOW}No source found in /proc/cmdline${NORMAL}"
	server=$defaultsource
fi

# download the configuration file
echo "${BLUE}Downloading configuration from $server${NORMAL}"

devices=$(ls /sys/class/net/ | grep -v lo | grep -v dummy)

for device in $devices "default"; do
	if [ "$device" = "default" ]; then
		echo "${YELLOW}Getting default config...${NORMAL}"
		address="default"
	else
		address=`cat /sys/class/net/$device/address`
		echo "${BLUE}Device ${YELLOW}$device ${BLUE}has MAC ${YELLOW}$address${BLUE}, looking for config...${NORMAL}"
	fi
	wget $server/$address -O /tmp/config
	if [ $? -eq 0 ]; then
		break
	fi
done

# split the config into sections
mkdir /tmp/configs
awk '/LABEL/{n++}{print >"/tmp/configs/"n }' /tmp/config

# and display menu if we need to
if [ "`ls -1 /tmp/configs/ | wc -l`" = "1" ]; do
	echo "${BLUE}Only one boot item specified, skipping menu...${NORMAL}"
else
	show_menu
fi

# parse values and download payload
b_server="`cat /tmp/config | grep SERVER | cut -d' ' -f2-`"
b_kernel="`cat /tmp/config | grep KERNEL | cut -d' ' -f2-`"
b_initrd="`cat /tmp/config | grep INITRD | cut -d' ' -f2-`"
b_append="`cat /tmp/config | grep APPEND | cut -d' ' -f2-`"

if [ "$b_server" = "" ]; then
	b_server=$server
fi
if [ "$b_kernel" = "" ]; then
	echo "${RED}The configuration source did not provide a kernel${NORMAL}"
	end_early
else
	echo "${BLUE}Downloading kernel...${NORMAL}"
	check_download $b_server/$b_kernel /tmp/kernel
fi
if [ "$b_initrd" = "" ]; then
	echo "The configuration source did not provide a initrd${NORMAL}"
else
	echo "${BLUE}Downloading initrd...${NORMAL}"
	check_download $b_server/$b_initrd /tmp/initrd
fi
if [ "$b_append" = "" ]; then
	echo "${YELLOW}The configuration source did not provide any append arguments${NORMAL}"
fi

# do the kexec
echo "${BLUE}Preparing to kexec the new kernel...${NORMAL}"
if [ "$b_initrd" = "" ]; then
	kexec -l /tmp/kernel --command-line="$b_append" || end_early
else
	kexec -l /tmp/kernel --command-line="$b_append" --initrd=/tmp/initrd || end_early
fi

kexec -e

# this should be the end, otherwise...

echo "${RED}The new kernel failed to load.${NORMAL}"
end_early