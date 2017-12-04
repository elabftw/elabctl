#!/usr/bin/env bash
# https://www.elabftw.net

###############################################################
# CONFIGURATION
# where is the source code?
declare CODE_DIR="${HOME}/elabftw"
# where do you want your backups to end up?
declare BACKUP_DIR='/var/backups/elabftw'
# where do we store the config file?
declare CONF_FILE='/etc/elabftw.yml'
# where do we store the MySQL database and the uploaded files?
declare DATA_DIR='/var/elabftw'
# where do we store the logs?
declare LOG_FILE='/var/log/elabftw.log'
# END CONFIGURATION
###############################################################

declare -r MAN_FILE='/usr/share/man/man1/elabctl.1.gz'
declare -r ELABCTL_VERSION='0.6.3'
declare -r USER_CONF_FILE='/etc/elabctl.conf'

# Now we load the configuration file for custom directories set by user
if [ -f ${USER_CONF_FILE} ]; then
    source ${USER_CONF_FILE}
fi

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
    echo "If something goes wrong, have a look at ${LOG_FILE}!"
}

# create a mysqldump and a zip archive of the uploaded files
function backup()
{
    echo "Using backup directory $BACKUP_DIR"

    if ! ls -A "${BACKUP_DIR}" > /dev/null 2>&1; then
        mkdir -p "${BACKUP_DIR}"
    fi

    set -e

    # get clean date
    local -r date=$(date --iso-8601) # 2016-02-10
    local -r zipfile="${BACKUP_DIR}/uploaded_files-${date}.zip"
    local -r dumpfile="${BACKUP_DIR}/mysql_dump-${date}.sql"

    # dump sql
    docker exec mysql bash -c 'mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -r dump.sql $MYSQL_DATABASE' > /dev/null 2>&1
    # copy it from the container to the host
    docker cp mysql:dump.sql "$dumpfile"
    # compress it to the max
    gzip -f --best "$dumpfile"
    # make a zip of the uploads folder
    zip -rq "$zipfile" ${DATA_DIR}/web -x ${DATA_DIR}/web/tmp\*
    # add the config file
    zip -rq "$zipfile" $CONF_FILE

    echo "Done. Copy ${BACKUP_DIR} over to another computer."
}

# generate info for reporting a bug
function bugreport()
{
    echo "Collecting information for a bug report…"
    echo -n "elabctl version: "
    version
    echo -n "elabftw version: "
    docker exec -t elabftw git tag|tail -n 1
    echo "operating system: "
    cat /etc/os-release
    uname -a
    free -h
}

function compile-messages()
{
    for po_file in `find $CODE_DIR/app/locale/ -name "messages.po"`; do
        echo "Compiling ${po_file}"
        mo_file=${po_file/%.po/.mo}
        msgfmt -o $mo_file $po_file
    done
}

function detectOS()
{
    if test -e /etc/os-release; then
        source /etc/os-release
        OS=$ID

    elif [ `uname` == "Darwin" ]; then
        OS='macos'

    # for CentOS 6.8, see #368
    elif grep -qi centos /etc/*-release; then
        echo "It looks like you are using CentOS 6.8 which is using a very old kernel not compatible/stable with Docker. It is not recommended to use eLabFTW in Docker with this setup. Please have a look at the installation instructions without Docker."
        exit 1

    else
        echo "Could not detect your OS. Please open a github issue!"
        exit 1
    fi
}

function getUserconf()
{
    # do not overwrite a custom conf file
    if [ ! -f $USER_CONF_FILE ]; then
        wget -qO- https://github.com/elabftw/elabctl/raw/master/elabctl.conf > $USER_CONF_FILE
    fi
}

function getDeps()
{
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ] || [ "$OS" == "linuxmint" ]; then
        echo "Synchronizing packages index. Please wait…"
        apt-get update >> $LOG_FILE 2>&1
    elif [ "$OS" == "macos" ] && ! hash brew 2>/dev/null; then
        echo "Installing prerequisite package: brew. Please wait…"
        # See https://brew.sh/
        /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    fi

    if ! hash dialog 2>/dev/null; then
        echo "Installing prerequisite package: dialog. Please wait…"
        install-pkg dialog
    fi

    if ! hash zip 2>/dev/null; then
        echo "Installing prerequisite package: zip. Please wait…"
        install-pkg zip
    fi

    if ! hash wget 2>/dev/null; then
        echo "Installing prerequisite package: wget. Please wait…"
        install-pkg wget
    fi

    if ! hash git 2>/dev/null; then
        echo "Installing prerequisite package: git. Please wait…"
        install-pkg git
    fi

    if ! hash gettext 2>/dev/null; then
        echo "Installing prerequisite package: gettext. Please wait…"
        install-pkg gettext
        if [ "$OS" == "macos" ]; then
            brew link --force gettext
        fi
    fi
}

function getDistrib()
{
    # pacman = package manager

    # DEBIAN / UBUNTU / MINT
    if [ "$OS" == "ubuntu" ] || [ "$OS" == "debian" ] || [ "$OS" == "linuxmint" ]; then
        PACMAN="apt-get -y install"

    # FEDORA
    elif [ "$OS" == "fedora" ]; then
        PACMAN="dnf -y install"

    # CENTOS
    elif [ "$OS" == "centos" ]; then
        PACMAN="yum -y install"
        # we need this to install python-pip
        install-pkg epel-release

    # RED HAT
    elif [ "$OS" == "rhel" ]; then
        PACMAN="yum -y install"

    # ARCH IS THE BEST
    elif [ "$OS" == "arch" ]; then
        PACMAN="pacman -Sy --noconfirm"

    # OPENSUSE
    elif [ "$OS" == "opensuse" ]; then
        PACMAN="zypper -n install"

    # MACOS
    elif [ "$OS" == "macos" ]; then
        PACMAN="brew install"

    else
        echo "What distribution are you running? Please open a github issue!"
        exit 1
    fi
}

# install manpage
function getMan()
{
    wget -qO- https://github.com/elabftw/elabctl/raw/master/elabctl.1.gz > $MAN_FILE
}

function help()
{
    version
    echo "
    Usage: elabctl [OPTION] [COMMAND]
           elabctl [ --help | --version ]
           elabctl install
           elabctl backup

    Commands:

        backup            Backup your installation
        bugreport         Gather information about the system for a bug report
        compile-messages  Compile translation files
        help              Show this text
        info              Display the configuration variables and status
        install           Configure and install required components
        logs              Show logs of the containers
        php-logs          Show last 15 lines of nginx error log
        refresh           Recreate the containers if they need to be
        restart           Restart the containers
        self-update       Update the elabctl script
        status            Show status of running containers
        start             Start the containers
        stop              Stop the containers
        uninstall         Uninstall eLabFTW and purge data
        update            Get the latest version of the containers
        version           Display elabctl version

    See 'man elabctl' for more informations."
}

function info()
{
    echo "Backup directory: ${BACKUP_DIR}"
    echo "Data directory: ${DATA_DIR}"
    echo "Log file: ${LOG_FILE}"
    echo "Man file: ${MAN_FILE}"
    echo ""
    echo "Status:"
    status
}

function infos()
{
    info
}

# install pip and docker-compose, get elabftw.yml and configure it with sed
function install()
{
    # init vars
    # mysql passwords
    declare rootpass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
    declare pass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)

    # if you don't want any dialog
    declare unattended=${ELAB_UNATTENDED:-0}
    declare servername=${ELAB_SERVERNAME:-localhost}
    declare hasdomain=${ELAB_HASDOMAIN:-0}
    declare email=${ELAB_EMAIL:-elabtest@yopmail.com}
    declare usele=${ELAB_USELE:-0}
    declare usehttps=${ELAB_USEHTTPS:-1}
    declare useselfsigned=${ELAB_USESELFSIGNED:-0}

    # exit on error
    set -e

    title="Install eLabFTW"
    backtitle="eLabFTW installation"

    ascii
    getDistrib
    getDeps

    # show welcome screen and ask if defaults are fine
    if [ "$unattended" -eq 0 ]; then
        # because answering No to dialog equals exit != 0
        set +e

        # welcome screen
        dialog --backtitle "$backtitle" --title "$title" --msgbox "\nWelcome to the install of eLabFTW :)\n
        This script will automatically install eLabFTW in a Docker container." 0 0

        dialog --colors --backtitle "$backtitle" --title "$title" --yes-label "Looks good to me" --no-label "Download example conf and quit" --yesno "\nHere is what will happen:\n
        The main configuration file will be created at: \Z4${CONF_FILE}\Zn\n
        The configuration file for elabctl will be created at: \Z4${USER_CONF_FILE}\Zn\n
        A directory holding elabftw data (mysql + uploaded files) will be created at: \Z4${DATA_DIR}\Zn\n
        A log file of the installation process will be created at: \Z4${LOG_FILE}\Zn\n
        A man page for elabctl will be added to your system\n
        The backups will be created at: \Z4${BACKUP_DIR}\Zn\n\n
        If you wish to change the defaults paths, quit now and edit the file \Z4${USER_CONF_FILE}\Zn" 0 0
        if [ $? -eq 1 ]; then
            echo "Downloading an example configuration file to \Z4${USER_CONF_FILE}\Zn"
            getUserconf
            echo "Done. You can now edit this file and restart the installation afterwards."
            exit 0
        fi
    fi

    # create the data dir
    mkdir -p $DATA_DIR

    # do nothing if there are files in there
    if [ "$(ls -A $DATA_DIR)" ]; then
        echo "It looks like eLabFTW is already installed. Delete the ${DATA_DIR} folder to reinstall."
        exit 1
    fi

    getMan
    getUserconf

    if [ "$unattended" -eq 0 ]; then
        set +e
        ########################################################################
        # start asking questions                                               #
        # what we want here is the domain name of the server or its IP address #
        # and also if we want to use Let's Encrypt or not
        ########################################################################

        # ASK SERVER OR LOCAL?
        dialog --backtitle "$backtitle" --title "$title" --yes-label "Server" --no-label "My computer" --yesno "\nAre you installing it on a Server or a personal computer?" 0 0
        if [ $? -eq 1 ]; then
            # local computer
            servername="localhost"
        else
            # server

            ## DOMAIN NAME OR IP BLOCK
            dialog --backtitle "$backtitle" --title "$title" --yesno "\nIs a domain name pointing to this server?\n\nAnswer yes if this server can be reached using a domain name. Answer no if you can only reach it with an IP address.\n" 0 0
            if [ $? -eq 0 ]; then
                hasdomain=1
                # ask for domain name
                servername=$(dialog --backtitle "$backtitle" --title "$title" --inputbox "\nPlease enter your domain name below:\nExample: elabftw.example.org\n" 0 0 --output-fd 1)
            else
                # ask for ip
                servername=$(dialog --backtitle "$backtitle" --title "$title" --inputbox "\nPlease enter your IP address below:\nExample: 88.120.132.154\n" 0 0 --output-fd 1)
            fi
            ## END DOMAIN NAME OR IP BLOCK

            # ASK IF WE WANT HTTPS AT ALL FIRST
            dialog --backtitle "$backtitle" --title "$title" --yes-label "Use HTTPS" --no-label "Disable HTTPS" --yesno "\nDo you want to run the HTTPS enabled container or a normal HTTP server? Note: disabling HTTPS means you will use another webserver as a proxy for TLS connections.\n\nChoose 'Disable HTTPS' if you already have a webserver capable of terminating TLS requests running (Apache or nginx).\nChoose 'Use HTTPS' if unsure.\n" 0 0
            if [ $? -eq 1 ]; then
                # use HTTP
                usehttps=0
            else
                # use HTTPS
                # https + no domain = self signed
                if [ $hasdomain -eq 0 ]; then
                    useselfsigned=1
                else
                    # ASK IF SELF-SIGNED OR PROPER CERT
                    dialog --backtitle "$backtitle" --title "$title" --yes-label "Use correct certificate" --no-label "Use self-signed" --yesno "\nDo you want to use a proper TLS certificate (coming from Let's Encrypt or provided by you) or use a self-signed certificate? The self-signed certificate will be automatically generated for you, but browsers will display a warning when connecting.\n\nChoose 'Use self-signed' if you do not have a domain name.\n" 0 0
                    if [ $? -eq 1 ]; then
                        useselfsigned=1
                    else
                        # want correct cert
                        # ASK FOR LETSENCRYPT
                        dialog --colors --backtitle "$backtitle" --title "$title" --yes-label "Use Let's Encrypt" --no-label "Use my own certificate" --yesno "\nDo you want to request a free certificate from Let's Encrypt or use one you already have?\n\n\ZbIMPORTANT:\Zn you can only use Let's Encrypt if you have a domain name pointing to this server and it is accessible from internet (not behind a corporate network).\nChoose 'Use my own certificate' if you don't want elabctl to install the Let's Encrypt client to request a new certificate." 0 0
                        if [ $? -eq 0 ]; then
                            usele=1
                            hasdomain=1
                            email=$(dialog --backtitle "$backtitle" --title "$title" --inputbox "\nWhat is your email?\n
        It is sent to Let's Encrypt only so they can remind you about certificate expiration.\n
        Enter your email address:\n" 0 0 --output-fd 1)
                        else
                            # show warning about need of edit config file for own certs
                            dialog --colors --backtitle "$backtitle" --title "$title" --msgbox "\nMake sure to \Zb\Z4edit the configuration file ${CONF_FILE}\Zn to point to your certificates before starting the containers!\n" 0 0
                        fi
                    fi
                fi
            fi
        fi
    fi



    set -e

    echo 10 | dialog --backtitle "$backtitle" --title "Installing required packages" --gauge "Installing python-pip" 20 80
    install-pkg python-pip >> "$LOG_FILE" 2>&1

    echo 20 | dialog --backtitle "$backtitle" --title "Installing required packages" --gauge "Installing python-setuptools" 20 80
    install-pkg python-setuptools >> "$LOG_FILE" 2>&1

    echo 30 | dialog --backtitle "$backtitle" --title "Installing required packages" --gauge "Installing docker-compose" 20 80
    # make sure we have the latest pip version
    pip install --upgrade pip >> "$LOG_FILE" 2>&1
    pip install --upgrade docker-compose >> "$LOG_FILE" 2>&1

    echo 40 | dialog --backtitle "$backtitle" --title "$title" --gauge "Creating folder structure" 20 80
    mkdir -pv ${DATA_DIR}/{web,mysql} >> "$LOG_FILE" 2>&1
    chmod -R 700 ${DATA_DIR} >> "$LOG_FILE" 2>&1
    chown -v 999:999 ${DATA_DIR}/mysql >> "$LOG_FILE" 2>&1
    chown -v 100:101 ${DATA_DIR}/web >> "$LOG_FILE" 2>&1
    sleep 1

    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Grabbing the docker-compose configuration file" 20 80
    # make a copy of an existing conf file
    if [ -e $CONF_FILE ]; then
        echo 55 | dialog --backtitle "$backtitle" --title "$title" --gauge "Making a copy of the existing configuration file." 20 80
        \cp $CONF_FILE ${CONF_FILE}.old
    fi

    wget -q https://raw.githubusercontent.com/elabftw/elabimg/master/src/docker-compose.yml-EXAMPLE -O "$CONF_FILE"
    # setup restrictive permissions
    chmod 600 "$CONF_FILE"
    sleep 1

    # elab config
    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Adjusting configuration" 20 80
    secret_key=$(curl --silent https://demo.elabftw.net/install/generateSecretKey.php)
    sed -i -e "s/SECRET_KEY=/SECRET_KEY=$secret_key/" $CONF_FILE
    sed -i -e "s/SERVER_NAME=localhost/SERVER_NAME=$servername/" $CONF_FILE
    sed -i -e "s:/var/elabftw:${DATA_DIR}:" $CONF_FILE

    # disable https
    if [ $usehttps = 0 ]; then
        sed -i -e "s/DISABLE_HTTPS=false/DISABLE_HTTPS=true/" $CONF_FILE
    fi

    # enable letsencrypt
    if [ $hasdomain -eq 1 ]; then
        # even if we don't use Let's Encrypt, for using TLS certs we need this to be true, and volume mounted
        sed -i -e "s:ENABLE_LETSENCRYPT=false:ENABLE_LETSENCRYPT=true:" $CONF_FILE
        sed -i -e "s:#- /etc/letsencrypt:- /etc/letsencrypt:" $CONF_FILE
    fi

    # mysql config
    sed -i -e "s/MYSQL_ROOT_PASSWORD=secr3t/MYSQL_ROOT_PASSWORD=$rootpass/" $CONF_FILE
    sed -i -e "s/MYSQL_PASSWORD=secr3t/MYSQL_PASSWORD=$pass/" $CONF_FILE
    sed -i -e "s/DB_PASSWORD=secr3t/DB_PASSWORD=$pass/" $CONF_FILE

    sleep 1

    # install letsencrypt and request a certificate
    if  [ $hasdomain -eq 1 ] && [ $usele -eq 1 ]; then
        echo 60 | dialog --backtitle "$backtitle" --title "$title" --gauge "Installing letsencrypt in ${DATA_DIR}/letsencrypt" 20 80
        git clone --depth 1 --branch master https://github.com/letsencrypt/letsencrypt ${DATA_DIR}/letsencrypt >> $LOG_FILE 2>&1
        echo 65 | dialog --backtitle "$backtitle" --title "$title" --gauge "Allowing traffic on port 443" 20 80
        ufw allow 443/tcp || true
        echo 70 | dialog --backtitle "$backtitle" --title "$title" --gauge "Getting the SSL certificate" 20 80
        cd ${DATA_DIR}/letsencrypt && ./letsencrypt-auto certonly --standalone --email "$email" --agree-tos --non-interactive -d "$servername"
    fi

    # final screen
    if [ $unattended -eq 0 ]; then
        dialog --colors --backtitle "$backtitle" --title "Installation finished" --msgbox "\nCongratulations, eLabFTW was successfully installed! :)\n\n
        \Z1====>\Zn Start the containers with: \Zb\Z4elabctl start\Zn\n\n
        It will take a minute or two to run at first.\n\n
        \Z1====>\Zn Go to https://$servername once started!\n\n
        In the mean time, check out what to do after an install:\n
        \Z1====>\Zn https://doc.elabftw.net/postinstall.html\n\n
        The log file of the install is here: $LOG_FILE\n
        The configuration file for docker-compose is here: \Z4$CONF_FILE\Zn\n
        Your data folder is: \Z4${DATA_DIR}\Zn. It contains the MySQL database and uploaded files.\n
        You can use 'docker logs -f elabftw' to follow the starting up of the container.\n
        See 'man elabctl' to backup or update." 20 80
    fi

}

function install-pkg()
{
    $PACMAN "$1" >> $LOG_FILE 2>&1
}

function is-root()
{
    if [ $EUID != 0 ]; then
        echo "You don't have sufficient permissions. Try with:"
        echo "sudo elabctl $1"
        exit 1
    fi
}

function is-installed()
{
    if [ ! -f $CONF_FILE ]; then
        echo "###### ERROR ##########################################################"
        echo "Configuration file could not be found! Did you run the install command?"
        echo "#######################################################################"
        exit 1
    fi
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

function refresh()
{
    start
}


function restart()
{
    stop
    start
}

function self-update()
{
    getMan
    wget -qO- https://raw.githubusercontent.com/elabftw/elabctl/master/elabctl.sh > /tmp/elabctl
    chmod +x /tmp/elabctl
    mv /tmp/elabctl /usr/bin/elabctl
}

function start()
{
    is-installed
    docker-compose -f "$CONF_FILE" up -d
}

function status()
{
    docker-compose -f "$CONF_FILE" ps
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

    set +e

    dialog --backtitle "$backtitle" --title "$title" --yesno "\nWarning! You are about to delete everything related to eLabFTW on this computer!\n\nThere is no 'go back' button. Are you sure you want to do this?\n" 0 0
    if [ $? != 0 ]; then
        exit 1
    fi

    dialog --backtitle "$backtitle" --title "$title" --yesno "\nDo you want to delete the backups, too?" 0 0
    if [ $? -eq 0 ]; then
        rmbackup='y'
    else
        rmbackup='n'
    fi

    dialog --backtitle "$backtitle" --title "$title" --ok-label "Skip timer" --cancel-label "Cancel uninstall" --pause "\nRemoving everything in 10 seconds. Stop now you fool!\n" 20 40 10
    if [ $? != 0 ]; then
        exit 1
    fi

    clear

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
    if [ $rmbackup == 'y' ] && [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR"
        echo "[x] Deleted $BACKUP_DIR"
    fi

    # remove docker images
    docker rmi elabftw/elabimg || true
    docker rmi mysql:5.7 || true

    echo ""
    echo "[✓] Everything has been obliterated. Have a nice day :)"
}

function update()
{
    echo "Before updating, a backup will be created."
    backup
    echo "Backup done, now updating."
    docker-compose -f "$CONF_FILE" pull
    restart
}

function upgrade()
{
    update
}

function usage()
{
    help
}

function version()
{
    echo "elabctl © 2017 Nicolas CARPi - https://www.elabftw.net"
    echo "Version: $ELABCTL_VERSION"
}

# SCRIPT BEGIN

detectOS
if [ "$OS" != "macos" ]; then
    is-root
fi

# only one argument allowed
if [ $# != 1 ]; then
    help
    exit 1
fi

# deal with --help and --version
case "$1" in
    -h|--help)
    help
    exit 0
    ;;
    -v|--version)
    version
    exit 0
    ;;
esac

# available commands
declare -A commands
for valid in backup bugreport compile-messages help info infos install logs php-logs self-update start status stop refresh restart uninstall update upgrade usage version
do
    commands[$valid]=1
done

if [[ ${commands[$1]} ]]; then
    # exit if variable isn't set
    set -u
    version
    echo "Using configuration file: "$CONF_FILE""
    echo ""
    $1
else
    help
    exit 1
fi
