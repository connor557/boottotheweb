#!/bin/sh
# BootToTheWeb init script
# Copyright (c) 2015 Joshua Higgins
# Released under the terms of the GNU GPL v3

. /etc/init.d/tc-functions

m_echo ()
{
	# show all messages above loglevel 3
	# loglevel 3 is default (hide messages, show errors)
	if [ `getbootparam loglevel` -gt 3 ]; then
		echo $@
	fi
}

e_echo ()
{
	# show errors above loglevel 2
	if [ `getbootparam loglevel` -gt 2 ]; then
		echo $@
	fi
}

end_early ()
{
	e_echo ""
	e_echo "${WHITE}The system cannot start.${NORMAL}"
	read -p "Press [Enter] key to reboot"
	reboot
}

prepend_http () {
	echo "$1" | grep "http://" > /dev/null 2>&1
	if [ $? -ne 0 ]; then
		echo "http://$1"
	else
		echo "$1"
	fi
}

check_download ()
{
	wget `prepend_http $1` -O $2
	if [ $? -ne 0 ]; then
		e_echo "${RED}There was an error downloading the file ${YELLOW}$1${NORMAL}"
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

m_echo "${GREEN}BootToTheWeb ${YELLOW}version 1.0${NORMAL}"

# configure the network
m_echo "${BLUE}Configuring network...${NORMAL}"
udhcpc || end_early

# try and get server from /proc/cmdline
# otherwise use default source
defaultsource="http://platformctrl.com"

server="`getbootparam server`"

if [ "$server" = "" ]; then
	m_echo "${YELLOW}No source found in /proc/cmdline${NORMAL}"
	server=$defaultsource
fi

# get proxy
export http_proxy="`getbootparam proxy`"
export https_proxy="`getbootparam proxy`"

# download the configuration file
m_echo "${BLUE}Downloading configuration from $server${NORMAL}"

devices=$(ls /sys/class/net/ | grep -v lo | grep -v dummy)

for device in $devices "default"; do
	if [ "$device" = "default" ]; then
		m_echo "${YELLOW}Getting default config...${NORMAL}"
		address="default"
	else
		address=`cat /sys/class/net/$device/address`
		m_echo "${BLUE}Device ${YELLOW}$device ${BLUE}has MAC ${YELLOW}$address${BLUE}, looking for config...${NORMAL}"
	fi
	wget `prepend_http $server/$address` -O /tmp/config
	if [ $? -eq 0 ]; then
		break
	fi
done

# split the config into sections
mkdir /tmp/configs
awk '/LABEL/{n++}{print >"/tmp/configs/"n }' /tmp/config

# and display menu if we need to
if [ "`ls -1 /tmp/configs/ | wc -l`" = "1" ]; then
	m_echo "${BLUE}Only one boot item specified, skipping menu...${NORMAL}"
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
	e_echo "${RED}The configuration source did not provide a kernel${NORMAL}"
	end_early
else
	m_echo "${BLUE}Downloading kernel...${NORMAL}"
	check_download $b_server/$b_kernel /tmp/kernel
fi
if [ "$b_initrd" = "" ]; then
	m_echo "The configuration source did not provide a initrd${NORMAL}"
else
	m_echo "${BLUE}Downloading initrd...${NORMAL}"
	check_download $b_server/$b_initrd /tmp/initrd
fi
if [ "$b_append" = "" ]; then
	m_echo "${YELLOW}The configuration source did not provide any append arguments${NORMAL}"
fi

# do the kexec
m_echo "${BLUE}Preparing to kexec the new kernel...${NORMAL}"
if [ "$b_initrd" = "" ]; then
	kexec -l /tmp/kernel --command-line="$b_append" || end_early
else
	kexec -l /tmp/kernel --command-line="$b_append" --initrd=/tmp/initrd || end_early
fi

kexec -e

# this should be the end, otherwise...

e_echo "${RED}The new kernel failed to load.${NORMAL}"
end_early