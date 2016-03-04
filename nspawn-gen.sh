#!/bin/bash

# Site Config
DISTRO=$1
NAME=$2
CONTAINER_DIR=/var/lib/container/
FULL_PATH=$CONTAINER_DIR/$NAME/
DEBOOTSTRAP_SCRIPTS=/usr/share/debootstrap/scripts/
NETIF=eth1
# dbus required to avoid error below when attempting machinectl login
# Failed to get container bus: Input/output error
PACKAGES="dbus"

# Container specific values
MACADDR=$(echo $NAME | md5sum | sed 's/^\(..\)\(..\)\(..\)\(..\)\(..\).*$/02:\1:\2:\3:\4:\5/')

if [ $# -eq 0 ]; then
    echo "usage: $0 <distro> <container name>"
    exit 1
fi

if [ $(id -u) -gt 0 ]; then
    echo "I think this should be run as root."
    exit 1
fi

if [ ! -f $DEBOOTSTRAP_SCRIPTS/$1 ]; then
    echo "Debootstrap script $1 does not exist"
    exit 1
fi


echo "Beginning to bootstrap $1 to $FULL_PATH."
/usr/sbin/debootstrap --include $PACKAGES $1 $FULL_PATH
echo "Symlinking resolvconf"
ln -sf $FULL_PATH/run/systemd/resolve/resolv.conf $FULL_PATH/etc/resolv.conf
echo "Creating $FULL_PATH/etc/systemd/network/mv-$NETIF.network"
cat > $FULL_PATH/etc/systemd/network/mv-$NETIF.network << EOF
[Match]
Name=mv-eth1

[Network]
DHCP=yes

[Link]
MACAddress=$MACADDR

EOF

    /usr/bin/systemd-nspawn --directory=$FULL_PATH systemctl enable systemd-networkd.service systemd-resolved.service

    echo "Creating /etc/systemd/system/container-$NAME.service"
    cat > /etc/systemd/system/container-$NAME.service << EOF
[Unit]
Description=Container $NAME

[Service]
ExecStart=/usr/bin/systemd-nspawn --quiet --keep-unit --link-journal=try-guest --directory=$FULL_PATH --network-macvlan=$NETIF --boot
KillMode=mixed
Type=notify
RestartForceExitStatus=133
SuccessExitStatus=133

[Install]
WantedBy=multi-user.target
EOF

echo "Creating hostname file"
echo $NAME > $FULL_PATH/etc/hostname

echo "Adding pts/0 to securetty"
echo "pts/0" >> $FULL_PATH/etc/securetty
