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

logfile='/var/log/elabftw.log'
conffile='/etc/elabftw.yml'
datadir='/var/elabftw'

function install()
{
    # mysql passwords
    rootpass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
    pass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    hasdomain='n'
    domain=$ip

    # install dialog first
    echo "Preparing installation. Please wait…"
    apt-get update >> $logfile 2>&1
    echo "Almost done…"
    DEBIAN_FRONTEND=noninteractive apt-get -y install dialog >> $logfile 2>&1

    # display ascii logo
    dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --msgbox "\nWelcome to the install of eLabFTW :)\n
    This script will automatically install eLabFTW in a Docker container." 0 0

    set +e
    # get info for letsencrypt and nginx
    dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --yesno "\nIs a domain name pointing to this server?\n\nAnswer yes if this server can be reached using a domain name. In this case a proper SSL certificate will be requested from Let's Encrypt.\n\nAnswer no if you can only reach this server using an IP address. In this case a self-signed certificate will be used." 0 0
    if [ $? -eq 0 ]
    then
        set -e
        hasdomain='y'
        domain=$(dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --inputbox "\nCool, we will use Let's Encrypt :)\n
    What is the domain name of this server?\n
    Example : elabftw.ktu.edu\n
    Enter your domain name:\n" 0 0 --output-fd 1)
        email=$(dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --inputbox "\nLast question, what is your email?\n
    It is sent to Let's Encrypt only.\n
    Enter your email address:\n" 0 0 --output-fd 1)
    fi

    set -e

    echo 10 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Installing python-pip" 20 80
    DEBIAN_FRONTEND=noninteractive apt-get -y install \
        python-pip >> $logfile 2>&1

    echo 30 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Installing docker-compose" 20 80
    pip install -U docker-compose >> $logfile 2>&1

    echo 40 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Creating folder structure" 20 80
    mkdir -pvm 777 /elabftw/{web,mysql} >> $logfile 2>&1

    echo 50 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Grabbing the docker-compose configuration file" 20 80
    wget -q https://raw.githubusercontent.com/elabftw/docker-elabftw/master/src/docker-compose.yml-EXAMPLE -O $conffile


    echo 50 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Adjusting configuration" 20 80
    # elab config
    secret_key=$(curl -s https://demo.elabftw.net/install/generateSecretKey.php)
    sed -i -e "s/SECRET_KEY=/SECRET_KEY=$secret_key/" $conffile
    sed -i -e "s/SERVER_NAME=localhost/SERVER_NAME=$domain/" $conffile
    sed -i -e "s:/dok/uploads:$datadir/web:" $conffile

    # enable letsencrypt
    if [ $hasdomain == 'y' ]
    then
        sed -i -e "s:ENABLE_LETSENCRYPT=false:ENABLE_LETSENCRYPT=true:" $conffile
        sed -i -e "s:#- /etc/letsencrypt:- /etc/letsencrypt:" $conffile
    fi

    # mysql config
    sed -i -e "s/MYSQL_ROOT_PASSWORD=secr3t/MYSQL_ROOT_PASSWORD=$rootpass/" $conffile
    sed -i -e "s/MYSQL_PASSWORD=secr3t/MYSQL_PASSWORD=$pass/" $conffile
    sed -i -e "s/DB_PASSWORD=secr3t/DB_PASSWORD=$pass/" $conffile
    sed -i -e "s:/dok/mysql:$datadir/mysql:" $conffile

    if  [ $hasdomain == 'y' ]
    then
        echo 60 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Installing letsencrypt in /letsencrypt" 20 80
        git clone --depth 1 -b master https://github.com/letsencrypt/letsencrypt /letsencrypt >> $logfile 2>&1
        echo 70 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Getting the SSL certificate" 20 80
        cd /letsencrypt && ./letsencrypt-auto certonly --standalone --email $email --agree-tos -d $domain
    fi

    echo 80 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Setting up automatic startup after boot" 20 80
    sed -i -e "s:exit 0:cd /root \&\& /usr/local/bin/docker-compose -f $conffile up -d:" /etc/rc.local

    echo 90 | dialog --backtitle "eLabFTW installation" --title "Install in the cloud" --gauge "Launching Docker" 20 80
    cd /root && docker-compose -f $conffile up -d

    dialog --backtitle "eLabFTW installation" --title "Installation finished" --msgbox "\nCongratulations, eLabFTW was successfully installed! :)\n
    It will take a minute or two to run at first.\n\n
    ====> Go to https://$domain/install in a minute!\n\n
    In the mean time, check out what to do after an install:\n
    ====> https://elabftw.readthedocs.io/en/hypernext/postinstall.html\n\n
    The log file of the install is here: $logfile\n
    The configuration file for docker-compose is here: $conffile\n
    You can use 'docker logs -f elabftw' to follow the starting up of the container." 20 80
}

function update()
{
    docker-compose -f $conffile pull
    restart
}

function start()
{
    docker-compose -f $conffile up -d
}

function stop()
{
    docker-compose -f $conffile down
}

function restart()
{
    docker-compose -f $conffile down
    docker-compose -f $conffile up -d
}

function status()
{
    docker ps
}

function logs()
{
    docker logs mysql
    docker logs elabftw
}

function php-logs()
{
    docker exec elabftw tail -n 15 /var/log/nginx/error.log
}

function usage()
{
    echo "Usage: elabctl install|update|start|stop|restart|status|logs|php-logs"
    exit 1
}

if [ $# -eq 1 ];
then
    $1
else
    usage
fi
