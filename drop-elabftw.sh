#!/bin/bash
# http://www.elabftw.net

# exit on error
set -e

# exit if variable isn't set
set -u

# root only
if [ $EUID != 0 ];then
    echo "Why u no root?"
    exit 1
fi

logfile='elabftw.log'

# mysql passwords
rootpass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
pass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
ip=$(dig +short myip.opendns.com @resolver1.opendns.com)

# display ascii logo
clear
echo ""
echo "  ___ | |  ____ | |__   / _|| |_ __      __"
echo " / _ \| | / _ ||| |_ \ | |_ | __|\ \ /\ / /"
echo "|  __/| || (_| || |_) ||  _|| |_  \ V  V / "
echo " \___||_| \__,_||_.__/ |_|   \__|  \_/\_/  "
echo ""

# get info for letsencrypt and nginx
echo "[:)] Welcome to the install of elabftw!"
echo "[?] What is the domain name of this server?"
echo "[*] Example : elabftw.ktu.edu"
echo "[!] WARNING: don't put the IP address!"
read -p "[?] Your domain name: " domain
echo "[?] Second and last question, what is your email?"
echo "[!] It is sent only to letsencrypt"
read -p "[?] Your email: " email

echo "[*] Updating packages list"
apt-get update >> $logfile 2>&1

echo "[*] Installing python-pip"
DEBIAN_FRONTEND=noninteractive apt-get -y install \
    python-pip >> $logfile 2>&1

echo "[*] Installing docker-compose"
pip install -U docker-compose >> $logfile 2>&1

echo "[*] Creating folder structure"
mkdir -pvm 777 /elabftw/{web,mysql} >> $logfile 2>&1

echo "[*] Grabbing the docker-compose configuration file"
wget -q https://raw.githubusercontent.com/elabftw/docker-elabftw/master/src/docker-compose.yml-EXAMPLE -O docker-compose.yml

echo "[*] Adjusting configuration"
# elab config
secret_key=$(curl -s https://demo.elabftw.net/install/generateSecretKey.php)
sed -i -e "s/SECRET_KEY=/SECRET_KEY=$secret_key/" docker-compose.yml
sed -i -e "s/SERVER_NAME=localhost/SERVER_NAME=$domain/" docker-compose.yml
sed -i -e "s:/dok/uploads:/elabftw/web:" docker-compose.yml

# enable letsencrypt
sed -i -e "s:ENABLE_LETSENCRYPT=false:ENABLE_LETSENCRYPT=true:" docker-compose.yml
sed -i -e "s:#- /etc/letsencrypt:- /etc/letsencrypt:" docker-compose.yml

# mysql config
sed -i -e "s/MYSQL_ROOT_PASSWORD=secr3t/MYSQL_ROOT_PASSWORD=$rootpass/" docker-compose.yml
sed -i -e "s/MYSQL_PASSWORD=secr3t/MYSQL_PASSWORD=$pass/" docker-compose.yml
sed -i -e "s/DB_PASSWORD=secr3t/DB_PASSWORD=$pass/" docker-compose.yml
sed -i -e "s:/dok/mysql:/elabftw/mysql:" docker-compose.yml

echo "[*] Installing letsencrypt in /letsencrypt"
git clone --depth 1 -b master https://github.com/letsencrypt/letsencrypt /letsencrypt >> $logfile 2>&1

echo "[*] Getting the SSL certificate"
cd /letsencrypt && ./letsencrypt-auto certonly --standalone --email $email --agree-tos -d $domain

echo "[*] Setting up automatic startup after boot"
sed -i -e "s:exit 0:cd /root \&\& /usr/local/bin/docker-compose -d:" /etc/rc.local

echo "[*] Launching docker"
cd /root && docker-compose up -d

echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "Congratulations, eLabFTW was successfully installed! :)"
echo "It will take a minute or two to run at first."
echo "====> Go to https://$domain/install in a minute! <===="
echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
