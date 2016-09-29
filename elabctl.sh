#!/bin/bash
# http://www.elabftw.net

###############################################################
# CONFIGURATION
# where do you want your backups to end up?
backupdir='/var/backups/elabftw'
# where do we store the config file?
conffile='/etc/elabftw.yml'
# where do we store the MySQL database and the uploaded files?
datadir='/var/elabftw'
# where do we store the logs?
logfile='/var/log/elabftw.log'
# END CONFIGURATION
###############################################################

manpage='/usr/man/man1/elabctl.1.gz'
version='0.1.2'

function backup()
{
    if ! $(ls -A $backupdir > /dev/null 2>&1); then
        mkdir -p $backupdir
    fi

    set -e

    # get clean date
    date=$(date --iso-8601) # 2016-02-10
    zipfile="$backupdir/uploaded_files-$date.zip"
    dumpfile="$backupdir/mysql_dump-$date.sql"

    # dump sql
    docker exec -it mysql bash -c 'mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -r dump.sql $MYSQL_DATABASE' > /dev/null 2>&1
    # copy it from the container to the host
    docker cp mysql:dump.sql $dumpfile
    # compress it to the max
    gzip -f --best $dumpfile
    # make a zip of the uploads folder
    zip -rq $zipfile $datadir/web -x $datadir/web/tmp\*
    # add the config file
    zip -rq $zipfile $conffile

    echo "Done. Copy $backupdir over to another computer."
}

function getDeps()
{
    if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
        apt-get update >> $logfile 2>&1
    fi

    if ! $(hash dialog 2>/dev/null); then
        echo "Preparing installation. Please wait…"
        install-pkg dialog
    fi

    if ! $(hash zip 2>/dev/null); then
        echo "Preparing installation. Please wait…"
        install-pkg zip
    fi

    if ! $(hash wget 2>/dev/null); then
        echo "Preparing installation. Please wait…"
        install-pkg wget
    fi

    if ! $(hash dig 2>/dev/null); then
        echo "Preparing installation. Please wait…"
        install-pkg bind-utils
    fi
}

function getDistrib()
{
    # let's first try to read /etc/os-release
    if test -e /etc/os-release
    then

        # source the file
        . /etc/os-release

        # pacman = package manager

        # DEBIAN / UBUNTU
        if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
            PACMAN="apt-get -y install"

        # FEDORA
        elif [ "$ID" == "fedora" ]; then
            PACMAN="dnf -y install"

        # RED HAT / CENTOS
        elif [ "$ID" == "centos" ] || [ "$ID" == "rhel" ]; then
            PACMAN="yum -y install"
            # we need this to install python-pip
            wget -q http://dl.fedoraproject.org/pub/epel/7/x86_64/e/epel-release-7-8.noarch.rpm -O /tmp/epel.rpm
            rpm -ivh /tmp/epel.rpm

        # ARCH IS THE BEST
        elif [ "$ID" == "arch" ]; then
            PACMAN="pacman -Sy --noconfirm"

        # OPENSUSE
        elif [ "$ID" == "opensuse" ]; then
            PACMAN="zypper -n install"
        else
            echo "What distribution are you running? Please open a github issue!"
            exit 1
        fi
    fi
}

# install manpage
function getMan()
{
    wget -qO- https://github.com/elabftw/drop-elabftw/raw/master/elabctl.1.gz > /usr/share/man/man1/elabctl.1.gz
}

function help()
{
    version
    echo "
    Usage: elabctl [COMMAND]
           elabctl [ help | version ]

    Commands:

        backup          Backup your installation
        install         Install eLabFTW and start the containers
        logs            Show logs of the containers
        php-logs        Show last 15 lines of nginx error log
        self-update     Update the elabctl script
        status          Show status of running containers
        start           Start the containers
        stop            Stop the containers
        restart         Restart the containers
        update          Get the latest version of the containers

    See 'man elabctl' for more informations."
}

function init()
{
    getDistrib
    getDeps
    getMan
}

# install elabftw
function install()
{
    mkdir -p $datadir

    if [ "$(ls -A $datadir)" ]; then
        echo "It looks like eLabFTW is already installed. Delete the $datadir folder to reinstall."
        exit 1
    fi

    # exit on error
    set -e

    init

    # mysql passwords
    rootpass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
    pass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)

    set +e
    ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
    # dns requests might be blocked
    if [ $? != 0 ]; then
        # let's try to get the local IP with ip
        if $(hash ip 2>/dev/null); then
            ip=$(ip -4 addr | grep 'state UP' -A2| grep inet| awk '{print $2}' | cut -f1 -d'/'|head -n1)
        else
            ip="localhost"
        fi
    fi
    set -e

    hasdomain='n'
    domain=$ip
    title="Install eLabFTW"
    backtitle="eLabFTW installation"

    set +e

    # welcome screen
    dialog --backtitle "$backtitle" --title "$title" --msgbox "\nWelcome to the install of eLabFTW :)\n
    This script will automatically install eLabFTW in a Docker container." 0 0

    # get info for letsencrypt and nginx
    dialog --backtitle "$backtitle" --title "$title" --yesno "\nIs a domain name pointing to this server?\n\nAnswer yes if this server can be reached using a domain name. In this case a proper SSL certificate will be requested from Let's Encrypt.\n\nAnswer no if you can only reach this server using an IP address. In this case a self-signed certificate will be used." 0 0
    if [ $? -eq 0 ]
    then
        set -e
        hasdomain='y'
        domain=$(dialog --backtitle "$backtitle" --title "$title" --inputbox "\nCool, we will use Let's Encrypt :)\n
    What is the domain name of this server?\n
    Example : elabftw.ktu.edu\n
    Enter your domain name:\n" 0 0 --output-fd 1)
        email=$(dialog --backtitle "$backtitle" --title "$title" --inputbox "\nLast question, what is your email?\n
    It is sent to Let's Encrypt only.\n
    Enter your email address:\n" 0 0 --output-fd 1)
    fi

    set -e

    echo 10 | dialog --backtitle "$backtitle" --title "$title" --gauge "Installing python-pip" 20 80
    install-pkg python-pip >> $logfile 2>&1

    echo 30 | dialog --backtitle "$backtitle" --title "$title" --gauge "Installing docker-compose" 20 80
    # make sure we have the latest pip version
    pip install --upgrade pip >> $logfile 2>&1
    pip install -U docker-compose >> $logfile 2>&1

    echo 40 | dialog --backtitle "$backtitle" --title "$title" --gauge "Creating folder structure" 20 80
    mkdir -pvm 777 $datadir/{web,mysql} >> $logfile 2>&1
    sleep 1

    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Grabbing the docker-compose configuration file" 20 80
    # make a copy of an existing conf file
    if [ -e $conffile ]; then
        echo 55 | dialog --backtitle "$backtitle" --title "$title" --gauge "Making a copy of the existing configuration file." 20 80
        \cp $conffile $conffile.old
    fi

    wget -q https://raw.githubusercontent.com/elabftw/docker-elabftw/master/src/docker-compose.yml-EXAMPLE -O $conffile
    sleep 1

    # elab config
    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Adjusting configuration" 20 80
    secret_key=$(curl -s https://demo.elabftw.net/install/generateSecretKey.php)
    sed -i -e "s/SECRET_KEY=/SECRET_KEY=$secret_key/" $conffile
    sed -i -e "s/SERVER_NAME=localhost/SERVER_NAME=$domain/" $conffile

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

    sleep 1

    if  [ $hasdomain == 'y' ]
    then
        echo 60 | dialog --backtitle "$backtitle" --title "$title" --gauge "Installing letsencrypt in /letsencrypt" 20 80
        git clone --depth 1 -b master https://github.com/letsencrypt/letsencrypt $datadir/letsencrypt >> $logfile 2>&1
        echo 70 | dialog --backtitle "$backtitle" --title "$title" --gauge "Getting the SSL certificate" 20 80
        cd $datadir/letsencrypt && ./letsencrypt-auto certonly --standalone --email $email --agree-tos -d $domain
    fi

    dialog --backtitle "$backtitle" --title "Installation finished" --msgbox "\nCongratulations, eLabFTW was successfully installed! :)\n\n
    You can start the containers with: elabctl start\n\n
    It will take a minute or two to run at first.\n\n
    ====> Go to https://$domain/install once started!\n\n
    In the mean time, check out what to do after an install:\n
    ====> https://elabftw.readthedocs.io/en/hypernext/postinstall.html\n\n
    The log file of the install is here: $logfile\n
    The configuration file for docker-compose is here: $conffile\n
    Your data folder is: $datadir. It contains the MySQL database and uploaded files.\n
    You can use 'docker logs -f elabftw' to follow the starting up of the container.\n
    See 'man elabctl' to backup or update." 20 80
}

function install-pkg()
{
    $PACMAN $1 >> $logfile 2>&1
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

function restart()
{
    stop
    start
}

function self-update()
{
    wget -qO- https://raw.githubusercontent.com/elabftw/drop-elabftw/master/elabctl.sh > /usr/bin/elabctl && chmod +x /usr/bin/elabctl
    getMan
}

function start()
{
    docker-compose -f $conffile up -d
}

function status()
{
    docker ps
}

function stop()
{
    docker-compose -f $conffile down
}

function update()
{
    docker-compose -f $conffile pull
    restart
}

function usage()
{
    help
}

function version()
{
    echo "elabctl version $version"
}

# SCRIPT BEGIN

# root only
if [ $EUID != 0 ]; then
    echo "Only the root account can use this script."
    exit 1
fi

# check arguments
if [ $# != 1 ]; then
    help
    exit 1
fi

# available commands
declare -A commands
for valid in backup install logs php-logs self-update start status stop restart update usage version
do
    commands[$valid]=1
done

if [[ ${commands[$1]} ]]; then
    # exit if variable isn't set
    set -u
    $1
else
    help
    exit 1
fi
