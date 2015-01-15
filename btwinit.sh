#!/bin/sh
# BootToTheWeb init script
# Copyright (c) 2015 Joshua Higgins
# Released under the terms of the GNU GPL v3

. /etc/init.d/tc-functions

MESSAGE_LEVEL=3
ERROR_LEVEL=2

m_echo ()
{
	# show all messages above loglevel 3
	# loglevel 3 is default (hide messages, show errors)
	if [ `getbootparam loglevel` -gt $MESSAGE_LEVEL ]; then
		echo $@
	fi
}

d_echo ()
{
	# show in a dialog at loglevel 3
	if [ `getbootparam loglevel` -eq $MESSAGE_LEVEL ]; then
		length=`expr length "$1" + 4`
		dialog --infobox "$1" 3 $length
	else
		# otherwise pass to m_echo
		m_echo $1
	fi
}

e_echo ()
{
	# show errors above loglevel 2
	if [ `getbootparam loglevel` -gt $ERROR_LEVEL ]; then
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
	if [ `getbootparam loglevel` -gt $MESSAGE_LEVEL ]; then
		wget `prepend_http $1` -O $2
	else
		wget `prepend_http $1` -O $2 2>&1 > /dev/null
	fi
	if [ $? -ne 0 ]; then
		e_echo "${RED}There was an error downloading the file ${YELLOW}$1${NORMAL}"
		end_early
	fi
}

show_menu ()
{
	echo "Select an OS to start and press <Enter> key:"
	for x in $(ls /tmp/configs); do
		echo "$x) `cat /tmp/configs/$x | grep LABEL | cut -d' ' -f2-`"
	done
	read opt
	cp /tmp/configs/$opt /tmp/config
	if [ $? -ne 0 ]; then
		show_menu
	fi
}

show_dialog_menu () {
	choices=""
	for x in $(ls /tmp/configs); do
		choices="$choices $x \"`cat /tmp/configs/$x | grep LABEL | cut -d' ' -f2-`\""
	done
	echo "dialog --nocancel --menu \"Select an OS to start\" 0 0 0 $choices 2> /tmp/choice" > /tmp/menu
	sh /tmp/menu
	cp /tmp/configs/`cat /tmp/choice` /tmp/config
	if [ $? -ne 0 ]; then
		show_dialog_menu
	fi
}

# begin

# generate default dialogrc
dialog --create-rc ~/.dialogrc

m_echo "${GREEN}BootToTheWeb ${YELLOW}version 1.0${NORMAL}"

# configure the network
d_echo "Configuring network..."
if [ `getbootparam loglevel` -gt $MESSAGE_LEVEL ]; then
	udhcpc || end_early
else
	udhcpc 2>&1 > /dev/null || end_early
fi

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
d_echo "Downloading configuration from $server"

devices=$(ls /sys/class/net/ | grep -v lo | grep -v dummy)

for device in $devices "default"; do
	if [ "$device" = "default" ]; then
		m_echo "${YELLOW}Getting default config...${NORMAL}"
		address="default"
	else
		address=`cat /sys/class/net/$device/address`
		m_echo "${BLUE}Device ${YELLOW}$device ${BLUE}has MAC ${YELLOW}$address${BLUE}, looking for config...${NORMAL}"
	fi
	output="$(wget `prepend_http $server/$address` -O /tmp/config 2>&1)"
	status=$?
	m_echo $output
	if [ $status -eq 0 ]; then
		# wget didn't get an error, check for 404
		if [ "`cat /tmp/config`" = "404" ]; then
			m_echo "${YELLOW}No config for this device.${NORMAL}"
		else
			break
		fi
	else
		m_echo "${YELLOW}No config for this device.${NORMAL}"
	fi
done

# split the config into sections
mkdir -p /tmp/configs
awk '/LABEL/{n++}{print >"/tmp/configs/"n }' /tmp/config

# and display menu if we need to
if [ "`ls -1 /tmp/configs/ | wc -l`" = "1" ]; then
	m_echo "${BLUE}Only one boot item specified, skipping menu...${NORMAL}"
else
	# display a menu
	if [ `getbootparam loglevel` -gt $MESSAGE_LEVEL ]; then
		# preserve boot messages and show basic menu at loglevel > 3
		show_menu
	else
		# show dialog menu at loglevel <= 3
		show_dialog_menu
	fi
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
	d_echo "Downloading kernel..."
	check_download $b_server/$b_kernel /tmp/kernel
fi
if [ "$b_initrd" = "" ]; then
	m_echo "The configuration source did not provide a initrd${NORMAL}"
else
	d_echo "Downloading initrd..."
	check_download $b_server/$b_initrd /tmp/initrd
fi
if [ "$b_append" = "" ]; then
	m_echo "${YELLOW}The configuration source did not provide any append arguments${NORMAL}"
fi

# do the kexec
d_echo "Preparing to boot..."
if [ "$b_initrd" = "" ]; then
	kexec -l /tmp/kernel --command-line="$b_append" || end_early
else
	kexec -l /tmp/kernel --command-line="$b_append" --initrd=/tmp/initrd || end_early
fi

kexec -e

# this should be the end, otherwise...

e_echo "${RED}The new kernel failed to load.${NORMAL}"
end_early