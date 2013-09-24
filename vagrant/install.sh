#!/bin/bash
# Vagrant shell provisioner script. DO NOT RUN BY HAND.
# Author Ivan Mincik, GISTA s.r.o., ivan.mincik@gmail.com

# LTSP troubleshooting https://help.ubuntu.com/community/UbuntuLTSP/ClientTroubleshooting

set -e


GISLAB_VERSION=0.1~dev

#
### SERVER UPGRADE ###
#
export DEBIAN_FRONTEND=noninteractive
echo "PATH="$PATH:/vagrant/bin"" >> /etc/profile


# hold kernel packages from upgrade to avoid a need to restart server after
# installation (Vagrant box could provide up-to-date kernel image)
echo "linux-image-$(uname -r) hold" | dpkg --set-selections
echo "linux-generic-pae hold" | dpkg --set-selections
echo "linux-image-generic-pae hold" | dpkg --set-selections

echo "grub-pc hold" | dpkg --set-selections # hold also grub because of some issue

# set apt-cacher if available
#sed -i "s/deb http:\/\//deb http:\/\/<APT-CACHER IP>:3142\//" /etc/apt/sources.list

apt-get update
apt-get --assume-yes upgrade
apt-get --assume-yes install ltsp-server-standalone openssh-server isc-dhcp-server tftpd-hpa --no-install-recommends




#
### DHCP ###
#
# TODO: set some more exotic network range to avoid conflicts
cat << EOF > /etc/ltsp/dhcpd.conf
authoritative;

subnet 192.168.1.0 netmask 255.255.255.0 {
	range 192.168.1.200 192.168.1.250;
    option domain-name "osgis-lab.lan";
    option domain-name-servers 192.168.1.1, 8.8.8.8;
    option broadcast-address 192.168.1.255;
    option routers 192.168.1.1;
    option subnet-mask 255.255.255.0;
    option root-path "/opt/ltsp/i386";
    if substring( option vendor-class-identifier, 0, 9 ) = "PXEClient" {
        filename "/ltsp/i386/pxelinux.0";
    } else {
        filename "/ltsp/i386/nbi.img";
    }
}
EOF

cat << EOF > /etc/default/isc-dhcp-server
INTERFACES="eth1"
EOF

service isc-dhcp-server restart




#
### LTSP ###
#
echo "deb http://ppa.launchpad.net/imincik/gis/ubuntu precise main" >> /etc/apt/sources.list # add extra GIS repository
echo "deb http://ppa.launchpad.net/imincik/qgis2/ubuntu precise main" >> /etc/apt/sources.list # add extra QGIS 2 repository

# add some ltsp-build-client plugins which takes care about our image customizations
cp -av /vagrant/config/ltsp/plugins/ltsp-build-client/* /usr/share/ltsp/plugins/ltsp-build-client/Ubuntu/

# client image configuration
cat << EOF > /etc/ltsp/ltsp-build-client.conf
GISLAB_VERSION=$GISLAB_VERSION
ARCH=i386
FAT_CLIENT_DESKTOPS="xubuntu-desktop"
LATE_PACKAGES="
    vim
    htop
    mc
    rst2pdf
    libreoffice
    libreoffice-gtk
    libreoffice-calc
    libreoffice-writer
    gimp
    flashplugin-installer
    postgresql
    postgis
    postgresql-9.1-postgis
    pgadmin3
    qgis
    python-qgis
    qgis-plugin-grass
    grass
    gdal-bin
    libgdal1h
    python-gdal
    sqlite3
    spatialite-bin
    spatialite-gui
    git
    vim-gnome
    ipython
"
REMOVE_PACKAGES="
    thunderbird-globalmenu
    abiword
    abiword-common
    abiword-plugin-grammar
    abiword-plugin-mathview
    libabiword-2.9
    gnumeric
    gnumeric-common
    gnumeric-doc
"
EOF

ltsp-build-client --purge-chroot --copy-sourceslist --accept-unsigned-packages  # use --mirror http://<URL>:3142/sk.archive.ubuntu.com/ubuntu
																			    # or use --mount-package-cache --keep-packages to use local cache
ltsp-update-sshkeys
ltsp-update-kernels

# LTSP configuration
cat << EOF > /var/lib/tftpboot/ltsp/i386/lts.conf
[default]
LDM_SESSION=/usr/bin/startxfce4
LDM_THEME=gislab 
LOCAL_APPS=True
LOCAL_APPS_EXTRAMOUNTS=/vagrant/share
SCREEN_02=shell                          # get local root prompt when pressing Ctrl+Alt+F2 
SCREEN_07=ldm
EOF

service nbd-server restart

# disable plymouth screen for better client troubleshooting on boot
# sed -i "s/quiet splash plymouth:force-splash vt.handoff=7//" /var/lib/tftpboot/ltsp/i386/pxelinux.cfg/default




#
### USERS ###
#
/vagrant/bin/gislab-addusers.sh # call script to create user accounts


# vim: set ts=4 sts=4 sw=4 noet: