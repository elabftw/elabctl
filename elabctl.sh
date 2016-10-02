#!/usr/bin/env bash
# http://www.elabftw.net

###############################################################
# CONFIGURATION
# where do you want your backups to end up?
declare -r BACKUP_DIR='/var/backups/elabftw'
# where do we store the config file?
declare -r CONF_FILE='/etc/elabftw.yml'
# where do we store the MySQL database and the uploaded files?
declare -r DATA_DIR='/var/elabftw'
# where do we store the logs?
declare -r LOG_FILE='/var/log/elabftw.log'
# END CONFIGURATION
###############################################################

declare -r MAN_FILE='/usr/share/man/man1/elabctl.1.gz'
declare -r VERSION='0.2.1'

# display ascii logo
function ascii()
{
    clear
    echo ""
    echo "       _         _       __  _             "
    echo "  ___ | |  ____ | |__   / _|| |_ __      __"
    echo " / _ \| | / _ ||| |_ \ | |_ | __|\ \ /\ / /"
    echo "|  __/| || (_| || |_) ||  _|| |_  \ V  V / "
    echo " \___||_| \__,_||_.__/ |_|   \__|  \_/\_/  "
    echo ""
}

# create a mysqldump and a zip archive of the uploaded files
function backup()
{
    if ! $(ls -A $BACKUP_DIR > /dev/null 2>&1); then
        mkdir -p $BACKUP_DIR
    fi

    set -e

    # get clean date
    local -r date=$(date --iso-8601) # 2016-02-10
    local -r zipfile="${BACKUP_DIR}/uploaded_files-${date}.zip"
    local -r dumpfile="${BACKUP_DIR}/mysql_dump-${date}.sql"

    # dump sql
    docker exec -it mysql bash -c 'mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -r dump.sql $MYSQL_DATABASE' > /dev/null 2>&1
    # copy it from the container to the host
    docker cp mysql:dump.sql $dumpfile
    # compress it to the max
    gzip -f --best $dumpfile
    # make a zip of the uploads folder
    zip -rq $zipfile ${DATA_DIR}/web -x ${DATA_DIR}/web/tmp\*
    # add the config file
    zip -rq $zipfile $CONF_FILE

    echo "Done. Copy ${BACKUP_DIR} over to another computer."
}

function getDeps()
{
    if [ "$ID" == "ubuntu" ] || [ "$ID" == "debian" ]; then
        echo "Synchronizing packages index. Please wait…"
        apt-get update >> $LOG_FILE 2>&1
    fi

    if ! $(hash dialog 2>/dev/null); then
        echo "Installing prerequisite package: dialog. Please wait…"
        install-pkg dialog
    fi

    if ! $(hash zip 2>/dev/null); then
        echo "Installing prerequisite package: zip. Please wait…"
        install-pkg zip
    fi

    if ! $(hash wget 2>/dev/null); then
        echo "Installing prerequisite package: wget. Please wait…"
        install-pkg wget
    fi

    if ! $(hash dig 2>/dev/null); then
        echo "Installing prerequisite package: bind-utils. Please wait…"
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
    else
        echo "Could not load /etc/os-release to guess distribution. Please open a github issue!"
        exit 1
    fi
}

# install manpage
function getMan()
{
    wget -qO- https://github.com/elabftw/drop-elabftw/raw/master/elabctl.1.gz > $MAN_FILE
}

function help()
{
    version
    echo "
    Usage: elabctl [COMMAND]
           elabctl [ help | version ]

    Commands:

        backup          Backup your installation
        help            Show this text
        install         Configure and install required components
        logs            Show logs of the containers
        php-logs        Show last 15 lines of nginx error log
        restart         Restart the containers
        self-update     Update the elabctl script
        status          Show status of running containers
        start           Start the containers
        stop            Stop the containers
        uninstall       Uninstall eLabFTW and purge data
        update          Get the latest version of the containers
        version         Display elabctl version

    See 'man elabctl' for more informations."
}

function init()
{
    ascii
    getDistrib
    getDeps
    getMan
}

# install pip and docker-compose, get elabftw.yml and configure it with sed
function install()
{
    mkdir -p $DATA_DIR

    if [ "$(ls -A $DATA_DIR)" ]; then
        echo "It looks like eLabFTW is already installed. Delete the ${DATA_DIR} folder to reinstall."
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
    install-pkg python-pip >> $LOG_FILE 2>&1

    echo 30 | dialog --backtitle "$backtitle" --title "$title" --gauge "Installing docker-compose" 20 80
    # make sure we have the latest pip version
    pip install --upgrade pip >> $LOG_FILE 2>&1
    pip install --upgrade docker-compose >> $LOG_FILE 2>&1

    echo 40 | dialog --backtitle "$backtitle" --title "$title" --gauge "Creating folder structure" 20 80
    mkdir -pvm 777 ${DATA_DIR}/{web,mysql} >> $LOG_FILE 2>&1
    sleep 1

    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Grabbing the docker-compose configuration file" 20 80
    # make a copy of an existing conf file
    if [ -e $CONF_FILE ]; then
        echo 55 | dialog --backtitle "$backtitle" --title "$title" --gauge "Making a copy of the existing configuration file." 20 80
        \cp $CONF_FILE ${CONF_FILE}.old
    fi

    wget -q https://raw.githubusercontent.com/elabftw/docker-elabftw/master/src/docker-compose.yml-EXAMPLE -O $CONF_FILE
    sleep 1

    # elab config
    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Adjusting configuration" 20 80
    secret_key=$(curl --silent https://demo.elabftw.net/install/generateSecretKey.php)
    sed -i -e "s/SECRET_KEY=/SECRET_KEY=$secret_key/" $CONF_FILE
    sed -i -e "s/SERVER_NAME=localhost/SERVER_NAME=$domain/" $CONF_FILE

    # enable letsencrypt
    if [ $hasdomain == 'y' ]
    then
        sed -i -e "s:ENABLE_LETSENCRYPT=false:ENABLE_LETSENCRYPT=true:" $CONF_FILE
        sed -i -e "s:#- /etc/letsencrypt:- /etc/letsencrypt:" $CONF_FILE
    fi

    # mysql config
    sed -i -e "s/MYSQL_ROOT_PASSWORD=secr3t/MYSQL_ROOT_PASSWORD=$rootpass/" $CONF_FILE
    sed -i -e "s/MYSQL_PASSWORD=secr3t/MYSQL_PASSWORD=$pass/" $CONF_FILE
    sed -i -e "s/DB_PASSWORD=secr3t/DB_PASSWORD=$pass/" $CONF_FILE

    sleep 1

    if  [ $hasdomain == 'y' ]
    then
        echo 60 | dialog --backtitle "$backtitle" --title "$title" --gauge "Installing letsencrypt in /letsencrypt" 20 80
        git clone --depth 1 --branch master https://github.com/letsencrypt/letsencrypt ${DATA_DIR}/letsencrypt >> $LOG_FILE 2>&1
        echo 70 | dialog --backtitle "$backtitle" --title "$title" --gauge "Getting the SSL certificate" 20 80
        cd ${DATA_DIR}/letsencrypt && ./letsencrypt-auto certonly --standalone --email $email --agree-tos -d $domain
    fi

    dialog --backtitle "$backtitle" --title "Installation finished" --msgbox "\nCongratulations, eLabFTW was successfully installed! :)\n\n
    You can start the containers with: elabctl start\n\n
    It will take a minute or two to run at first.\n\n
    ====> Go to https://$domain/install once started!\n\n
    In the mean time, check out what to do after an install:\n
    ====> https://elabftw.readthedocs.io/en/hypernext/postinstall.html\n\n
    The log file of the install is here: $LOG_FILE\n
    The configuration file for docker-compose is here: $CONF_FILE\n
    Your data folder is: ${DATA_DIR}. It contains the MySQL database and uploaded files.\n
    You can use 'docker logs -f elabftw' to follow the starting up of the container.\n
    See 'man elabctl' to backup or update." 20 80
}

function install-pkg()
{
    $PACMAN $1 >> $LOG_FILE 2>&1
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
    getMan
    wget -qO- https://raw.githubusercontent.com/elabftw/drop-elabftw/master/elabctl.sh > /tmp/elabctl
    chmod +x /tmp/elabctl
    mv /tmp/elabctl /usr/bin/elabctl
}

function start()
{
    docker-compose -f "$CONF_FILE" up -d
}

function status()
{
    docker ps
}

function stop()
{
    docker-compose -f "$CONF_FILE" down
}

function uninstall()
{
    stop

    local -r backtitle="eLabFTW uninstall"
    local title="Uninstall"
    dialog --backtitle "$backtitle" --title "$title" --yesno "\nWarning! You are about to delete everything related to eLabFTW on this computer!\n\nThere is no 'go back' button. Are you sure you want to do this?\n" 0 0
    title="(O)"
    dialog --backtitle "$backtitle" --title "$title" --msgbox "\nDave, stop.\n" 0 0
    dialog --backtitle "$backtitle" --title "$title" --msgbox "\nStop, will you?\n" 0 0
    dialog --backtitle "$backtitle" --title "$title" --msgbox "\nStop, Dave.\n" 0 0
    dialog --backtitle "$backtitle" --title "$title" --msgbox "\nWill you stop, Dave?\n" 0 0
    dialog --backtitle "$backtitle" --title "$title" --msgbox "\nStop, Dave. I'm afraid.\n" 0 0

    clear
    echo "Removing everything in 10 seconds."
    echo "Press Ctrl-C now to abort!"
    for i in {10..1}
    do
        echo -n "${i}..."
        sleep 1
    done
    echo ""

    # remove man page
    if [ -f "$MAN_FILE" ]; then
        rm -f "$MAN_FILE"
        echo "[x] Deleted $MAN_FILE"
    fi

    # remove config file and eventual backup
    if [ -f "${CONF_FILE}.old" ]; then
        rm -f "${CONF_FILE}.old"
        echo "[x] Deleted ${CONF_FILE}.old"
    fi
    if [ -f "$CONF_FILE" ]; then
        rm -f "$CONF_FILE"
        echo "[x] Deleted $CONF_FILE"
    fi
    # remove logfile
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        echo "[x] Deleted $LOG_FILE"
    fi
    # remove data directory
    if [ -d "$DATA_DIR" ]; then
        rm -rf "$DATA_DIR"
        echo "[x] Deleted $DATA_DIR"
    fi
    # remove backup dir
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR"
        echo "[x] Deleted $BACKUP_DIR"
    fi

    # remove containers and images
    docker rm elabftw || true
    docker rm mysql || true
    docker rmi elabftw/docker-elabftw || true
    docker rmi mysql:5.7 || true

    echo "Everything has been obliterated. Have a nice day :)"
}

function update()
{
    docker-compose -f "$CONF_FILE" pull
    restart
}

function usage()
{
    help
}

function version()
{
    echo "elabctl version $VERSION"
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
for valid in backup help install logs php-logs self-update start status stop restart uninstall update usage version
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
