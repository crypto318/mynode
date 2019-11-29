#!/bin/bash

source /usr/share/mynode/mynode_config.sh

set -x
set -e

# Make sure time is in the log
date

# Shut down main services to save memory and CPU
systemctl stop electrs
systemctl stop lnd
systemctl stop quicksync
systemctl stop bitcoind

# Check if any dpkg installs have failed and correct
dpkg --configure -a


# Check for updates (might auto-install all updates later)
apt-get update


# Install any new software
export DEBIAN_FRONTEND=noninteractive
apt-get -y install fonts-dejavu
apt-get -y install pv sysstat network-manager unzip pkg-config libfreetype6-dev libpng-dev
apt-get -y install libatlas-base-dev libffi-dev libssl-dev glances python3-bottle
apt-get -y -qq install apt-transport-https ca-certificates
apt-get -y install libgmp-dev automake libtool libltdl-dev libltdl7
apt-get -y install xorg chromium openbox lightdm

# Make sure some software is removed
apt-get -y purge ntp # (conflicts with systemd-timedatectl)


# Install any pip software
pip install tzupdate virtualenv --no-cache-dir


# Install any pip3 software
pip3 install python-bitcointx --no-cache-dir
pip3 install lndmanage==0.8.0.1 --no-cache-dir   # Install LND Manage (keep up to date with LND)
pip3 install docker-compose --no-cache-dir


# Import Keys
curl https://keybase.io/roasbeef/pgp_keys.asc | gpg --import
curl https://raw.githubusercontent.com/JoinMarket-Org/joinmarket-clientserver/master/pubkeys/AdamGibson.asc | gpg --import
gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964


# Install docker
if [ ! -f /usr/bin/docker ]; then
    rm -f /tmp/docker_install.sh
    wget https://get.docker.com -O /tmp/docker_install.sh
    sed -i 's/sleep 20/sleep 1/' /tmp/docker_install.sh
    /bin/bash /tmp/docker_install.sh
fi

# Use systemd for managing docker
rm -f /etc/init.d/docker
rm -f /etc/systemd/system/multi-user.target.wants/docker.service
systemctl -f enable docker.service

groupadd docker || true
usermod -aG docker admin
usermod -aG docker bitcoin
usermod -aG docker root


# Upgrade BTC
echo "Upgrading BTC..."
set +e
BTC_VERSION="0.19.0.1"
ARCH="arm-linux-gnueabihf"
uname -a | grep aarch64
if [ $? = 0 ]; then
    ARCH="aarch64-linux-gnu"
fi
if [ $IS_X86 = 1 ]; then
    ARCH="x86_64-linux-gnu" 
fi
set -e
BTC_UPGRADE_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/bitcoin-$BTC_VERSION-$ARCH.tar.gz
BTC_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.btc_url
BTC_UPGRADE_SHA256SUM_URL=https://bitcoincore.org/bin/bitcoin-core-$BTC_VERSION/SHA256SUMS.asc
CURRENT=""
if [ -f $BTC_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $BTC_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$BTC_UPGRADE_URL" ]; then
    # Download and install Bitcoin
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download

    wget $BTC_UPGRADE_URL
    wget $BTC_UPGRADE_SHA256SUM_URL -O SHA256SUMS.asc

    sha256sum --ignore-missing --check SHA256SUMS.asc
    if [ $? == 0 ]; then
        gpg --verify SHA256SUMS.asc
        if [ $? == 0 ]; then
            # Install Bitcoin
            tar -xvf bitcoin-$BTC_VERSION-$ARCH.tar.gz
            mv bitcoin-$BTC_VERSION bitcoin
            install -m 0755 -o root -g root -t /usr/local/bin bitcoin/bin/*

            # Mark current version
            echo $BTC_UPGRADE_URL > $BTC_UPGRADE_URL_FILE
        else
            echo "ERROR UPGRADING BITCOIN - GPG FAILED"
        fi
    else
        echo "ERROR UPGRADING BITCOIN - SHASUM FAILED"
    fi
fi

# Upgrade LND
echo "Upgrading LND..."
LND_VERSION="v0.8.1-beta"
LND_ARCH="lnd-linux-armv7"
if [ $IS_X86 = 1 ]; then
    LND_ARCH="lnd-linux-amd64"
fi
LND_UPGRADE_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/$LND_ARCH-$LND_VERSION.tar.gz
LND_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.lnd_url
LND_UPGRADE_MANIFEST_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt
LND_UPGRADE_MANIFEST_SIG_URL=https://github.com/lightningnetwork/lnd/releases/download/$LND_VERSION/manifest-$LND_VERSION.txt.sig
CURRENT=""
if [ -f $LND_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $LND_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$LND_UPGRADE_URL" ]; then
    # Download and install LND
    rm -rf /tmp/download
    mkdir -p /tmp/download
    cd /tmp/download

    wget $LND_UPGRADE_URL
    wget $LND_UPGRADE_MANIFEST_URL
    wget $LND_UPGRADE_MANIFEST_SIG_URL

    gpg --verify manifest-*.txt.sig
    if [ $? == 0 ]; then
        # Install LND
        tar -xzf lnd-*.tar.gz
        mv $LND_ARCH-$LND_VERSION lnd
        install -m 0755 -o root -g root -t /usr/local/bin lnd/*

        # Mark current version
        echo $LND_UPGRADE_URL > $LND_UPGRADE_URL_FILE
    else
        echo "ERROR UPGRADING LND - GPG FAILED"
    fi
fi

# Install recent version of secp256k1
echo "Installing secp256k1..."
if [ ! -f /usr/include/secp256k1_ecdh.h ]; then
    rm -rf /tmp/secp256k1
    cd /tmp/
    git clone https://github.com/bitcoin-core/secp256k1.git
    cd secp256k1

    ./autogen.sh
    ./configure
    make
    make install
    cp -f include/* /usr/include/
fi

# Upgrade Joinmarket
echo "Upgrading JoinMarket..."
if [ $IS_PREMIUM -eq 1 ]; then
    JOINMARKET_VERSION=0.5.5
    JOINMARKET_GITHUB_URL=https://github.com/JoinMarket-Org/joinmarket-clientserver.git
    JOINMARKET_VERSION_FILE=/home/bitcoin/.mynode/.joinmarket_version
    CURRENT=""
    if [ -f $JOINMARKET_VERSION_FILE ]; then
        CURRENT=$(cat $JOINMARKET_VERSION_FILE)
    fi
    if [ "$CURRENT" != "$JOINMARKET_VERSION" ]; then
        # Download and build JoinMarket
        cd /opt/mynode

        if [ ! -d /opt/mynode/joinmarket-clientserver ]; then
            git clone $JOINMARKET_GITHUB_URL
            cd joinmarket-clientserver
        else
            cd joinmarket-clientserver
            git pull origin master
        fi
        git reset --hard v$JOINMARKET_VERSION

        # Create virtualenv and setup joinmarket
        virtualenv -p python3 jmvenv
        source jmvenv/bin/activate
        python setupall.py --daemon
        python setupall.py --client-bitcoin
        deactivate

        echo $JOINMARKET_VERSION > $JOINMARKET_VERSION_FILE
    fi
fi

# Upgrade RTL
RTL_UPGRADE_URL=https://github.com/ShahanaFarooqui/RTL/archive/v0.5.1.tar.gz
RTL_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.rtl_url
CURRENT=""
if [ -f $RTL_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $RTL_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$RTL_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf RTL
    sudo -u bitcoin wget $RTL_UPGRADE_URL -O RTL.tar.gz
    sudo -u bitcoin tar -xvf RTL.tar.gz
    sudo -u bitcoin rm RTL.tar.gz
    sudo -u bitcoin mv RTL-* RTL
    cd RTL
    sudo -u bitcoin NG_CLI_ANALYTICS=false npm install --only=production
    
    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $RTL_UPGRADE_URL > $RTL_UPGRADE_URL_FILE
fi

# Upgrade Bitcoin RPC Explorer
BTCRPCEXPLORER_UPGRADE_URL=https://github.com/janoside/btc-rpc-explorer/archive/v1.1.1.tar.gz
BTCRPCEXPLORER_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.btcrpcexplorer_url
CURRENT=""
if [ -f $BTCRPCEXPLORER_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $BTCRPCEXPLORER_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$BTCRPCEXPLORER_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf btc-rpc-explorer
    sudo -u bitcoin wget $BTCRPCEXPLORER_UPGRADE_URL -O btc-rpc-explorer.tar.gz
    sudo -u bitcoin tar -xvf btc-rpc-explorer.tar.gz
    sudo -u bitcoin rm btc-rpc-explorer.tar.gz
    sudo -u bitcoin mv btc-rpc-* btc-rpc-explorer
    cd btc-rpc-explorer
    sudo -u bitcoin npm install --only=production

    mkdir -p /home/bitcoin/.mynode/
    chown -R bitcoin:bitcoin /home/bitcoin/.mynode/
    echo $BTCRPCEXPLORER_UPGRADE_URL > $BTCRPCEXPLORER_UPGRADE_URL_FILE
fi

# Upgrade WebSSH2
WEBSSH2_UPGRADE_URL=https://github.com/billchurch/webssh2/archive/v0.2.10-0.tar.gz
WEBSSH2_UPGRADE_URL_FILE=/home/bitcoin/.mynode/.webssh2_url
CURRENT=""
if [ -f $WEBSSH2_UPGRADE_URL_FILE ]; then
    CURRENT=$(cat $WEBSSH2_UPGRADE_URL_FILE)
fi
if [ "$CURRENT" != "$WEBSSH2_UPGRADE_URL" ]; then
    cd /opt/mynode
    rm -rf webssh2
    wget $WEBSSH2_UPGRADE_URL -O webssh2.tar.gz
    tar -xvf webssh2.tar.gz
    rm webssh2.tar.gz
    mv webssh2-* webssh2
    cd webssh2
    mv app/config.json.sample app/config.json
    docker build -t webssh2 .

    echo $WEBSSH2_UPGRADE_URL > $WEBSSH2_UPGRADE_URL_FILE
fi


# Install ngrok for debugging
if [ ! -f /usr/bin/ngrok  ]; then
    cd /tmp
    rm -rf /tmp/ngrok*
    NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-arm.zip
    if [ $IS_X86 = 1 ]; then
        NGROK_URL=https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-386.zip
    fi
    wget $NGROK_URL
    unzip ngrok-*.zip
    cp ngrok /usr/bin/
fi

# Enable any new/required services
systemctl enable firewall
systemctl enable invalid_block_check
systemctl enable usb_driver_check
systemctl enable https
systemctl enable glances
systemctl enable netdata
systemctl enable webssh2

# Disable any old services
sudo systemctl disable hitch
sudo systemctl disable mongodb
sudo systemctl disable lnd_admin

# Reload service settings
systemctl daemon-reload

# Sync FS
sync
