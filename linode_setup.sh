#!/bin/bash

function yesno {
  yesno_response="yes"
  echo -n "$1 ($yesno_response): "
  read yesno_response_in
  if test -n "${yesno_response_in}" ; then let yesno_response=yesno_response_in ; fi
  YESNO_RESPONSE="N"
  case $yesno_response in 
    [Yy]*) YESNO_RESPONSE="Y";;
  esac
}

function generate_preamble {
cat >> $SCRIPT_FILE <<END_OF_SCRIPT
#!/bin/bash
# 
# Script created $(date +%Y-%m-%d) by $(whoami) at $(hostname -f).
#

#
# These are the inputs
#
USERNAME=$USER
PASSWORD=$PASSWD
FULLNAME="$FULL_NAME"
HOSTNAME=$HOSTNAME
FQDN=$FQDN
IPADDRESS=$IP
SSH_KEY="$SSH_KEY"


# 
# Make sure we're fully updated
#
apt-get -qq update
apt-get -qq -y dist-upgrade
END_OF_SCRIPT
}

function generate_iptables_setup {
echo "Generating iptables setup."
cat >> $SCRIPT_FILE <<END_OF_SCRIPT

# Firewall, installation
apt-get -qq -y install iptables

# Firewall, setting up (reference: https://help.ubuntu.com/community/IptablesHowTo)
cat << EOF > /root/iptables.setup
# flush current tables (start from scratch)
iptables -F
# accept anything from localhost
iptables -A INPUT -i lo -j ACCEPT
# accept related connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# open ssh from outside
iptables -A INPUT -p tcp --dport ssh -j ACCEPT
# open web server connections from outside
iptables -A INPUT -p tcp --dport www -j ACCEPT
# open for BitTorrent
iptables -A INPUT -p tcp --destination-port 6881:6999 -j ACCEPT
# allow this server to be pinged
iptables -A INPUT -p icmp --icmp-type echo-request -j ACCEPT
# disallow everything else
iptables -A INPUT -j DROP
EOF

chmod a+x /root/iptables.setup
/root/iptables.setup

iptables-save > /etc/iptables.rules
chmod 600 /etc/iptables.rules

cat << EOF > /etc/network/if-pre-up.d/iptables
#!/bin/sh
iptables-restore < /etc/iptables.rules
EOF
chmod a+x /etc/network/if-pre-up.d/iptables

cat << EOF > /etc/network/if-post-down.d/iptables
#!/bin/sh
iptables-save -c > /etc/iptables.rules
EOF
chmod a+x /etc/network/if-post-down.d/iptables
END_OF_SCRIPT
}

function generate_utf8_fix {
echo "Generating locale fix for UTF8."
cat >> $SCRIPT_FILE <<END_OF_SCRIPT

# Fix locale bug on Ubuntu at Linode.com
locale-gen en_US.UTF-8
dpkg-reconfigure locales
END_OF_SCRIPT
}

function generate_hostname {
cat >> $SCRIPT_FILE <<END_OF_SCRIPT

# Hostname
hostname \$HOSTNAME
hostname > /etc/hostname
echo "     \$HOSTNAME" | cat - /etc/hosts > /etc/hosts.new
mv /etc/hosts.new /etc/hosts
END_OF_SCRIPT
}

function generate_user {
cat >> $SCRIPT_FILE <<END_OF_SCRIPT

# setup user
addgroup admin
echo -e "\n# Members of the admin group may gain root privileges" >> /etc/sudoers
echo "%admin ALL=(ALL) ALL" >> /etc/sudoers
echo "\$USERNAME::1000:\$USERNAME::/home/\$USERNAME:/bin/bash" | newusers
adduser \$USERNAME admin
mkdir -p /home/\$USERNAME/.ssh
touch /home/\$USERNAME/.ssh/authorized_keys
echo "\$SSH_KEY" > /home/\$USERNAME/.ssh/authorized_keys
chown -R \$USERNAME:\$USERNAME /home/\$USERNAME
chmod 600 /home/\$USERNAME/.ssh/authorized_keys
if grep PasswordAuthentication /etc/ssh/sshd_config > /dev/null ;
then sed -i.bak -r s/.*PasswordAuthentication.*/PasswordAuthentication\ no/g /etc/ssh/sshd_config ;
else echo "PasswordAuthentication no" >> /etc/ssh/sshd_config ;
fi
if grep PermitRootLogin /etc/ssh/sshd_config > /dev/null ;
then sed -i.bak -r s/.*PermitRootLogin.*/PermitRootLogin\ no/g /etc/ssh/sshd_config ;
else echo "PermitRootLogin no" >> /etc/ssh/sshd_config ;
fi
/etc/init.d/ssh restart
END_OF_SCRIPT
}

function generate_install_basic_tools {
cat >> $SCRIPT_FILE <<END_OF_SCRIPT

# Basic tools, installation
apt-get -qq -y install emacs screen wget unzip mailx rsync man

# Get a sane build environment
apt-get -qq -y install build-essential

# MySQL
apt-get -qq -y install mysql-server

# Version control
apt-get -qq -y install git-core subversion cvs
END_OF_SCRIPT
}

function generate_install_java {
echo "Generating installation of Sun JDK version 5 and 6 (and Ant, while we're at it)."
cat >> $SCRIPT_FILE <<END_OF_SCRIPT

# Java
apt-get -qq -y install sun-java6-jdk sun-java5-jdk ant ant-optional
END_OF_SCRIPT
}

function generate_install_ruby {
echo "Generating installation of Ruby packages."
cat >> $SCRIPT_FILE <<END_OF_SCRIPT

# Ruby
apt-get -qq -y install ruby-full libmysql-ruby 
# not sure if we want to apt-get rubygems or get it manually
# apt-get -qq -y install rubygems
# gem update --system

# Passenger (aka mod_rails). This will also include apache2
# Need to add the brightbox gpg key before installing
echo "deb http://apt.brightbox.net intrepid main" >> /etc/apt/sources.list
wget http://apt.brightbox.net/release.asc -O - | apt-key add -
apt-get -qq update
apt-get -qq -y install libapache2-mod-passenger
END_OF_SCRIPT
}

function transfer_and_execute_script {
  echo "The generated script will be scp-copied to root@$FQDN. Because of this, "
  echo "the scp program will ask you your root password for $FQDN."
  echo "scp $SCRIPT_FILE root@$FQDN:"
  echo "The script is now copied to root's home directory at $FQDN."
  echo "Now just log in as root@$FQDN and run it there. It can't be run from remote, "
  echo "since it will ask you a handful of questions when installing certain packages."
}

#################################################
#
# SCRIPT STARTS HERE
#
#################################################

echo "============================================================================================"
echo "="
echo "= Phase 1: Enter a bunch of parameters for your linode installation."
echo ""
echo -n "Fully Qualified Domain Name: "
read FQDN

HOSTNAME=$(echo $FQDN | cut -d . -f 1)

#echo "HOSTNAME = $HOSTNAME"

echo -n "Admin user (with sudo rights): "
read USER

echo -n "Password (Note! Your input will be visible!): "
read PASSWD

FULL_NAME=$USER
OLD_IFS="$IFS"
IFS=""
echo -n "Full name of user ($FULL_NAME): "
read FULL_NAME_IN
if test -n "$FULL_NAME_IN" ; then let FULL_NAME=FULL_NAME_IN ; fi
IFS="$OLD_IFS"

IP=$(host $FQDN | awk '{print $4}' | head -1)
echo -n "IP Address ($IP): "
read IP_IN
if test -n "$IP_IN" ; then let IP=IP_IN ; fi

SSH_KEYPATH=~/.ssh/id_rsa.pub
echo -n "Path to public SSH key ($SSH_KEYPATH): "
read SSH_KEYPATH_IN

if test -n "$SSH_KEYPATH_IN" ; then let SSH_KEYPATH=SSH_KEYPATH_IN ; fi

# if [ ! -e $SSH_KEYPATH } ; 

SSH_KEY=$(cat $SSH_KEYPATH)

SCRIPT_FILE="./linode_ubuntu_setup_${FQDN}_$(date +%Y%m%d_%H%M).sh"
echo -n "Name of generated setup script ($SCRIPT_FILE): "
read SCRIPT_FILE_IN
if test -n "$SCRIPT_FILE_IN" ; then let SCRIPT_FILE=SCRIPT_FILE_IN ; fi

touch $SCRIPT_FILE
chmod a+x $SCRIPT_FILE

yesno "Generate iptables setup?"
IPTABLES_SETUP=$YESNO_RESPONSE

yesno "Fix UTF8 locale conf?"
FIX_UTF8=$YESNO_RESPONSE

yesno "Install Sun's JDK (5 and 6)?"
INSTALL_JAVA=$YESNO_RESPONSE

yesno "Install Ruby environment?"
INSTALL_RUBY=$YESNO_RESPONSE


echo "============================================================================================"
echo "="
echo "= Phase 2: Generating setup script, $SCRIPT_FILE"
echo ""

generate_preamble
if [ "$IPTABLES_SETUP" == "Y" ] ; then generate_iptables_setup ; fi
if [ "$FIX_UTF8" == "Y" ] ; then generate_utf8_fix ; fi
generate_hostname
generate_user
generate_install_basic_tools
if [ "$INSTALL_JAVA" == "Y" ] ; then generate_install_java ; fi
if [ "$INSTALL_RUBY" == "Y" ] ; then generate_install_ruby ; fi
echo "Done generating script."

echo "============================================================================================"
echo "="
echo "= Phase 3: Execute script on $FQDN"
echo ""
yesno "Do you want to transfer the script to $FQDN and run it there?"
if [ $YESNO_RESPONSE == "Y" ] ; then transfer_and_execute_script ; fi

echo Done

