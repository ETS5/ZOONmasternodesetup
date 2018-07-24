#!/bin/bash
# ZOON zoonode Setup Script V1.3 for Ubuntu 16.04 LTS
# (c) 2018 by RUSH HOUR MINING for ZOON
#
# Script will attempt to autodetect primary public IP address
# and generate zoonode private key unless specified in command line
#
# Usage:
# bash ZOON-setup.sh [Zoonode_Private_Key]
#
# Example 1: Existing genkey created earlier is supplied
# bash ZOON-setup.sh 27dSmwq9CabKjo2L3UD1HvgBP3ygbn8HdNmFiGFoVbN1STcsypy
#
# Example 2: Script will generate a new genkey automatically
# bash ZOON-setup.sh
#

#Color codes
RED='\033[0;91m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#Reden TCP port
PORT=8328


#Clear keyboard input buffer
function clear_stdin { while read -r -t 0; do read -r; done; }

#Delay script execution for N seconds
function delay { echo -e "${GREEN}Sleep for $1 seconds...${NC}"; sleep "$1"; }

#Stop daemon if it's already running
function stop_daemon {
    if pgrep -x 'zoond' > /dev/null; then
        echo -e "${YELLOW}Attempting to stop zoond${NC}"
        zoon-cli stop
        delay 30
        if pgrep -x 'zoond' > /dev/null; then
            echo -e "${RED}zoond daemon is still running!${NC} \a"
            echo -e "${YELLOW}Attempting to kill...${NC}"
            pkill zoond
            delay 30
            if pgrep -x 'zoond' > /dev/null; then
                echo -e "${RED}Can't stop zoond! Reboot and try again...${NC} \a"
                exit 2
            fi
        fi
    fi
}

#Process command line parameters
genkey=$1

clear
echo -e "${YELLOW}ZOON Zoonode Setup Script V1.3 for Ubuntu 16.04 LTS${NC}"
echo -e "${GREEN}Updating system and installing required packages...${NC}"
sudo DEBIAN_FRONTEND=noninteractive apt-get update -y

# Determine primary public IP address
dpkg -s dnsutils 2>/dev/null >/dev/null || sudo apt-get -y install dnsutils
publicip=$(dig +short myip.opendns.com @resolver1.opendns.com)

if [ -n "$publicip" ]; then
    echo -e "${YELLOW}IP Address detected:" $publicip ${NC}
else
    echo -e "${RED}ERROR: Public IP Address was not detected!${NC} \a"
    clear_stdin
    read -e -p "Enter VPS Public IP Address: " publicip
    if [ -z "$publicip" ]; then
        echo -e "${RED}ERROR: Public IP Address must be provided. Try again...${NC} \a"
        exit 1
    fi
fi

# update packages and upgrade Ubuntu
sudo apt-get -y upgrade
sudo apt-get -y dist-upgrade
sudo apt-get -y autoremove
sudo apt-get -y install wget nano htop jq
sudo apt-get -y install libzmq3-dev
sudo apt-get -y install libboost-system-dev libboost-filesystem-dev libboost-chrono-dev libboost-program-options-dev libboost-test-dev libboost-thread-dev
sudo apt-get -y install libevent-dev

sudo apt -y install software-properties-common
sudo add-apt-repository ppa:bitcoin/bitcoin -y
sudo apt-get -y update
sudo apt-get -y install libdb4.8-dev libdb4.8++-dev

sudo apt-get -y install libminiupnpc-dev

sudo apt-get -y install fail2ban
sudo service fail2ban restart

sudo apt-get install ufw -y
sudo apt-get update -y

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow $PORT/tcp
sudo ufw allow 22/tcp
sudo ufw limit 22/tcp
echo -e "${YELLOW}"
sudo ufw --force enable
echo -e "${NC}"

#Generating Random Password for zooond JSON RPC
rpcuser=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
rpcpassword=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

#Create 2GB swap file
if grep -q "SwapTotal" /proc/meminfo; then
    echo -e "${GREEN}Skipping disk swap configuration...${NC} \n"
else
    echo -e "${YELLOW}Creating 2GB disk swap file. \nThis may take a few minutes!${NC} \a"
    touch /var/swap.img
    chmod 600 swap.img
    dd if=/dev/zero of=/var/swap.img bs=1024k count=2000
    mkswap /var/swap.img 2> /dev/null
    swapon /var/swap.img 2> /dev/null
    if [ $? -eq 0 ]; then
        echo '/var/swap.img none swap sw 0 0' >> /etc/fstab
        echo -e "${GREEN}Swap was created successfully!${NC} \n"
    else
        echo -e "${YELLOW}Operation not permitted! Optional swap was not created.${NC} \a"
        rm /var/swap.img
    fi
fi

#Installing Daemon
cd ~
sudo rm -r .zoon
sudo rm /usr/bin/zoon*
sudo rm ZOON-linux64.zip
wget https://github.com/cleanblockchain/zoon/releases/download/0.13/ZOON-linux64.zip
sudo unzip ZOON-linux64.zip
sudo rm ZOON-linux64.zip
sudo mv ~/ZOON ~/ZOONzoonodesetup/

stop_daemon

# Deploy binaries to /usr/bin
sudo cp ZOONzoonodesetup/ZOON/zoon* /usr/bin/
sudo chmod 755 -R ~/ZOONzoonodesetup
sudo chmod 755 /usr/bin/zoon*

# Deploy zoonode monitoring script
cp ~/ZOONzoonodesetup/nodemon.sh /usr/local/bin
sudo chmod 711 /usr/local/bin/nodemon.sh

#Create datadir
if [ ! -f ~/.zoon/zoon.conf ]; then 
	sudo mkdir ~/.zoon
fi

echo -e "${YELLOW}Creating zoon.conf...${NC}"

# If genkey was not supplied in command line, we will generate private key on the fly
if [ -z $genkey ]; then
    cat <<EOF > ~/.zoon/zoon.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
EOF

    sudo chmod 755 -R ~/.zoon/zoon.conf

    #Starting daemon first time just to generate zoonode private key
    zoond -daemon
    delay 30

    #Generate zoonode private key
    echo -e "${YELLOW}Generating zoonode private key...${NC}"
    genkey=$(zoon-cli zoonode genkey)
    if [ -z "$genkey" ]; then
        echo -e "${RED}ERROR: Can not generate zoonode private key.${NC} \a"
        echo -e "${RED}ERROR:${YELLOW}Reboot VPS and try again or supply existing genkey as a parameter.${NC}"
        exit 1
    fi
    
    #Stopping daemon to create zoon.conf
    stop_daemon
    delay 30
fi

# Create zoon.conf
cat <<EOF > ~/.zoon/zoon.conf
rpcuser=$rpcuser
rpcpassword=$rpcpassword
rpcallowip=127.0.0.1
onlynet=ipv4
listen=1
server=1
daemon=1
maxconnections=64
externalip=$publicip
zoonode=1
zoonodeprivkey=$genkey
EOF

#Finally, starting zoon daemon with new zoon.conf
zoond
delay 5

#Setting auto star cron job for zoond
cronjob="@reboot sleep 30 && zoond"
crontab -l > tempcron
if ! grep -q "$cronjob" tempcron; then
    echo -e "${GREEN}Configuring crontab job...${NC}"
    echo $cronjob >> tempcron
    crontab tempcron
fi
rm tempcron

echo -e "========================================================================
${YELLOW}zoonode setup is complete!${NC}
========================================================================
zoonode was installed with VPS IP Address: ${YELLOW}$publicip${NC}
zoonode Private Key: ${YELLOW}$genkey${NC}
Now you can add the following string to the zoonode.conf file
for your Hot Wallet (the wallet with your ZOON collateral funds):
======================================================================== \a"
echo -e "${YELLOW}mn1 $publicip:$PORT $genkey TxId TxIdx${NC}"
echo -e "========================================================================
Use your mouse to copy the whole string above into the clipboard by
tripple-click + single-click (Dont use Ctrl-C) and then paste it 
into your ${YELLOW}zoonode.conf${NC} file and replace:
    ${YELLOW}mn1${NC} - with your desired zoonode name (alias)
    ${YELLOW}TxId${NC} - with Transaction Id from zoonode outputs
    ${YELLOW}TxIdx${NC} - with Transaction Index (0 or 1)
     Remember to save the zoonode.conf and restart the wallet!
To introduce your new zoonode to the ZOON network, you need to
issue a zoonode start command from your wallet, which proves that
the collateral for this node is secured."

clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "1) Wait for the node wallet on this VPS to sync with the other nodes
on the network. Eventually the 'IsSynced' status will change
to 'true', which will indicate a comlete sync, although it may take
from several minutes to several hours depending on the network state.
Your initial zoonode Status may read:
    ${YELLOW}Node just started, not yet activated${NC} or
    ${YELLOW}Node  is not in zoonode list${NC}, which is normal and expected.
2) Wait at least until 'IsBlockchainSynced' status becomes 'true'.
At this point you can go to your wallet and issue a start
command by either using Debug Console:
    Tools->Debug Console-> enter: ${YELLOW}zoonode start-alias mn1${NC}
    where ${YELLOW}mn1${NC} is the name of your zoonode (alias)
    as it was entered in the zoonode.conf file
    
or by using wallet GUI:
    zoonodes -> Select zoonode -> RightClick -> ${YELLOW}start alias${NC}
Once completed step (2), return to this VPS console and wait for the
zoonode Status to change to: 'zoonode successfully started'.
This will indicate that your zoonode is fully functional and
you can celebrate this achievement!
Currently your zoonode is syncing with the ZOON network...
The following screen will display in real-time
the list of peer connections, the status of your zoonode,
node synchronization status and additional network and node stats.
"
clear_stdin
read -p "*** Press any key to continue ***" -n1 -s

echo -e "
${GREEN}...scroll up to see previous screens...${NC}
Here are some useful commands and tools for zoonode troubleshooting:
========================================================================
To view zoonode configuration produced by this script in reden.conf:
${YELLOW}cat ~/.zoon/zoon.conf${NC}
Here is your zoon.conf generated by this script:
-------------------------------------------------${YELLOW}"
cat ~/.zoon/zoon.conf
echo -e "${NC}-------------------------------------------------
NOTE: To edit zoon.conf, first stop the redend daemon,
then edit the reden.conf file and save it in nano: (Ctrl-X + Y + Enter),
then start the redend daemon back up:
to stop:   ${YELLOW}zoon-cli stop${NC}
to edit:   ${YELLOW}nano ~/.zoon/zoon.conf${NC}
to start:  ${YELLOW}zoond${NC}
========================================================================
To view zoond debug log showing all MN network activity in realtime:
${YELLOW}tail -f ~/.zoon/debug.log${NC}
========================================================================
To monitor system resource utilization and running processes:
${YELLOW}htop${NC}
========================================================================
To view the list of peer connections, status of your zoonode, 
sync status etc. in real-time, run the nodemon.sh script:
${YELLOW}nodemon.sh${NC}
or just type 'node' and hit <TAB> to autocomplete script name.
========================================================================
Enjoy your ZOON zoonode and thanks for using this setup script!
If you found it helpful, please donate ZOON to:
ofQzJU37B2a7G2EZ52qyhKjV6pAqJ3KYpp
...and make sure to check back for updates!
"
# Run nodemon.sh
nodemon.sh

# EOF
