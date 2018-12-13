#!/usr/bin/env bash
# https://www.elabftw.net
declare -r ELABCTL_VERSION='1.0.1'

# default backup dir
declare BACKUP_DIR='/var/backups/elabftw'
# default config file for docker-compose
declare CONF_FILE='/etc/elabftw.yml'
declare TMP_CONF_FILE='/tmp/elabftw.yml'
# default data directory
declare DATA_DIR='/var/elabftw'

# default conf file is no conf file
declare ELABCTL_CONF_FILE="using default values (no config file found)"

# display ascii logo
function ascii()
{
    echo ""
    echo "      _          _     _____ _______        __"
    echo "  ___| |    __ _| |__ |  ___|_   _\ \      / /"
    echo " / _ \ |   / _| | '_ \| |_    | |  \ \ /\ / / "
    echo "|  __/ |__| (_| | |_) |  _|   | |   \ V  V /  "
    echo " \___|_____\__,_|_.__/|_|     |_|    \_/\_/   "
    echo "                                              "
    echo ""
}

# create a mysqldump and a zip archive of the uploaded files
function backup()
{
    echo "Using backup directory $BACKUP_DIR"

    if ! ls -A "${BACKUP_DIR}" > /dev/null 2>&1; then
        mkdir -pv "${BACKUP_DIR}"
        if [ $? -eq 1 ]; then
            sudo mkdir -pv ${BACKUP_DIR}
        fi
    fi

    set -e

    # get clean date
    local -r date=$(date --iso-8601) # 2016-02-10
    local -r zipfile="${BACKUP_DIR}/uploaded_files-${date}.zip"
    local -r dumpfile="${BACKUP_DIR}/mysql_dump-${date}.sql"

    # dump sql
    docker exec mysql bash -c 'mysqldump -u$MYSQL_USER -p$MYSQL_PASSWORD -r dump.sql $MYSQL_DATABASE' || echo ">> Containers must be running to do the backup!"
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

function checkDeps()
{
    need_to_quit=0

    if ! hash dialog 2>/dev/null; then
        echo "Error: dialog not installed. Please install the program 'dialog'"
        need_to_quit=1
    fi
    if ! hash docker-compose 2>/dev/null; then
        echo "Error: docker-compose not installed. Please install the program 'docker-compose'"
        need_to_quit=1
    fi
    if ! hash git 2>/dev/null; then
        echo "Error: git not installed. Please install the program 'git'"
        need_to_quit=1
    fi
    if ! hash zip 2>/dev/null; then
        echo "Error: zip not installed. Please install the program 'zip'"
        need_to_quit=1
    fi

    if [ $need_to_quit -eq 1 ]; then
        exit 1
    fi
}

function get-user-conf()
{
    # download the config file in the current directory
    echo "Downloading the config file 'elabctl.conf' in current directory..."
    if [ -f elabctl.conf ]; then
        mv -v elabctl.conf elabctl.conf.old
    fi
    curl -Ls https://github.com/elabftw/elabctl/raw/master/elabctl.conf -o elabctl.conf
    echo "Downloaded elabctl.conf."
    echo "Edit it and move it in ~/.config or /etc."
    echo "Or leave it there and always use elabctl from this directory."
    echo "Then do 'elabctl install' again."
}

function has-disk-space()
{
    # check if we have enough space on disk to update the docker image
    docker_folder=$(docker info --format '{{.DockerRootDir}}')
    # use default if previous command didn't work
    safe_folder=${docker_folder:-/var/lib/docker}
    space_test=$(($(stat -f --format="%a*%S" $safe_folder)/1024**3 < 5))
    if [[ $space_test -ne 0 ]]; then
        echo "ERROR: There is less than 5 Gb of free space available on the disk where $safe_folder is located!"
        df -h $safe_folder
        echo ""
        read -p "Remove old images and containers to free up some space? (y/N)" -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker system prune
        fi
        exit 1
    fi
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

        backup          Backup your installation
        bugreport       Gather information about the system for a bug report
        help            Show this text
        info            Display the configuration variables and status
        install         Configure and install required components
        logs            Show logs of the containers
        mysql           Open a MySQL prompt in the 'mysql' container
        php-logs        Show last 15 lines of nginx error log
        refresh         Recreate the containers if they need to be
        restart         Restart the containers
        self-update     Update the elabctl script
        status          Show status of running containers
        start           Start the containers
        stop            Stop the containers
        uninstall       Uninstall eLabFTW and purge data
        update          Get the latest version of the containers
        version         Display elabctl version
    "
}

function info()
{
    echo "Backup directory: ${BACKUP_DIR}"
    echo "Data directory: ${DATA_DIR}"
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
    checkDeps

    # do nothing if there are files in there
    if [ "$(ls -A $DATA_DIR 2>/dev/null)" ]; then
        echo "It looks like eLabFTW is already installed. Delete the ${DATA_DIR} folder to reinstall."
        exit 1
    fi

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

    # show welcome screen and ask if defaults are fine
    if [ "$unattended" -eq 0 ]; then
        # because answering No to dialog equals exit != 0
        set +e

        # welcome screen
        dialog --backtitle "$backtitle" --title "$title" --msgbox "\nWelcome to the install of eLabFTW :)\n
        This script will automatically install eLabFTW in a Docker container." 0 0

        dialog --colors --backtitle "$backtitle" --title "$title" --yes-label "Looks good to me" --no-label "Download example conf and quit" --yesno "\nHere is what will happen:\n
        The main configuration file will be created at: \Z4${CONF_FILE}\Zn\n
        A directory holding elabftw data (mysql + uploaded files) will be created at: \Z4${DATA_DIR}\Zn\n
        The backups will be created at: \Z4${BACKUP_DIR}\Zn\n\n
        If you wish to change these settings, quit now and edit the file \Z4elabctl.conf\Zn" 0 0
        if [ $? -eq 1 ]; then
            get-user-conf
            exit 0
        fi
    fi

    # create the data dir
    mkdir -pv $DATA_DIR
    if [ $? -eq 1 ]; then
        sudo mkdir -pv $DATA_DIR
    fi

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

    echo 40 | dialog --backtitle "$backtitle" --title "$title" --gauge "Creating folder structure. You will be asked for your password (bottom left of the screen)." 20 80
    sudo mkdir -pv ${DATA_DIR}/{web,mysql}
    sudo chmod -Rv 700 ${DATA_DIR}
    echo "Executing: sudo chown -v 999:999 ${DATA_DIR}/mysql"
    sudo chown -v 999:999 ${DATA_DIR}/mysql
    echo "Executing: sudo chown -v 100:101 ${DATA_DIR}/web"
    sudo chown -v 100:101 ${DATA_DIR}/web
    sleep 2

    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Grabbing the docker-compose configuration file" 20 80
    # make a copy of an existing conf file
    if [ -e $CONF_FILE ]; then
        echo 55 | dialog --backtitle "$backtitle" --title "$title" --gauge "Making a copy of the existing configuration file." 20 80
        \cp $CONF_FILE ${CONF_FILE}.old
    fi

    curl -sL https://raw.githubusercontent.com/elabftw/elabimg/master/src/docker-compose.yml-EXAMPLE -o "$TMP_CONF_FILE"
    sleep 1

    # elab config
    echo 50 | dialog --backtitle "$backtitle" --title "$title" --gauge "Adjusting configuration" 20 80
    secret_key=$(curl --silent https://demo.elabftw.net/install/generateSecretKey.php)
    if [ "${#secret_key}" -eq 0 ]; then
        secret_key=$(curl --silent https://get.elabftw.net/?key)
        if [ "${#secret_key}" -eq 0 ]; then
            echo "Error getting secret key from demo.elabftw.net or get.elabftw.net! Maybe the server is down?"
            exit 1
        fi
    fi
    sed -i -e "s/SECRET_KEY=/SECRET_KEY=$secret_key/" $TMP_CONF_FILE
    sed -i -e "s/SERVER_NAME=localhost/SERVER_NAME=$servername/" $TMP_CONF_FILE
    sed -i -e "s:/var/elabftw:${DATA_DIR}:" $TMP_CONF_FILE

    # disable https
    if [ $usehttps = 0 ]; then
        sed -i -e "s/DISABLE_HTTPS=false/DISABLE_HTTPS=true/" $TMP_CONF_FILE
    fi

    # enable letsencrypt
    if [ $hasdomain -eq 1 ]; then
        # even if we don't use Let's Encrypt, for using TLS certs we need this to be true, and volume mounted
        sed -i -e "s:ENABLE_LETSENCRYPT=false:ENABLE_LETSENCRYPT=true:" $TMP_CONF_FILE
        sed -i -e "s:#- /etc/letsencrypt:- /etc/letsencrypt:" $TMP_CONF_FILE
    fi

    # mysql config
    sed -i -e "s/MYSQL_ROOT_PASSWORD=secr3t/MYSQL_ROOT_PASSWORD=$rootpass/" $TMP_CONF_FILE
    sed -i -e "s/MYSQL_PASSWORD=secr3t/MYSQL_PASSWORD=$pass/" $TMP_CONF_FILE
    sed -i -e "s/DB_PASSWORD=secr3t/DB_PASSWORD=$pass/" $TMP_CONF_FILE

    sleep 1

    # install letsencrypt and request a certificate
    if  [ $hasdomain -eq 1 ] && [ $usele -eq 1 ]; then
        echo 60 | dialog --backtitle "$backtitle" --title "$title" --gauge "Installing letsencrypt in ${DATA_DIR}/letsencrypt" 20 80
        git clone --depth 1 --branch master https://github.com/letsencrypt/letsencrypt ${DATA_DIR}/letsencrypt
        # because by default on DO drop it's closed
        echo 65 | dialog --backtitle "$backtitle" --title "$title" --gauge "Allowing traffic on port 443" 20 80
        ufw allow 443/tcp || true
        # also open the port 80 for the cert request
        ufw allow 80/tcp || true
        echo 70 | dialog --backtitle "$backtitle" --title "$title" --gauge "Getting the SSL certificate" 20 80
        cd ${DATA_DIR}/letsencrypt && ./letsencrypt-auto certonly --standalone --email "$email" --agree-tos --non-interactive -d "$servername"
    fi

    # setup restrictive permissions
    chmod 600 "$TMP_CONF_FILE"

    # now move conf file at proper location
    # use sudo in case it's in /etc and we are not root
    sudo mv "$TMP_CONF_FILE" "$CONF_FILE"

    # final screen
    if [ $unattended -eq 0 ]; then
        dialog --colors --backtitle "$backtitle" --title "Installation finished" --msgbox "\nCongratulations, eLabFTW was successfully installed! :)\n\n
        \Z1====>\Zn Start the containers with: \Zb\Z4elabctl start\Zn\n\n
        \Z1====>\Zn Go to https://$servername once started!\n\n
        In the mean time, check out what to do after an install:\n
        \Z1====>\Zn https://doc.elabftw.net/postinstall.html\n\n
        The configuration file for docker-compose is here: \Z4$CONF_FILE\Zn\n
        Your data folder is: \Z4${DATA_DIR}\Zn. It contains the MySQL database and uploaded files.\n
        You can use 'docker logs -f elabftw' to follow the starting up of the container.\n" 20 80
    fi

}

function is-installed()
{
    if [ ! -f $CONF_FILE ]; then
        echo "###### ERROR ##########################################################"
        echo "Configuration file (${CONF_FILE})  could not be found!"
        echo "Did you run the install command?"
        echo "#######################################################################"
        exit 1
    fi
}

function logs()
{
    docker logs mysql
    docker logs elabftw
}

function mysql()
{
    docker exec -it mysql bash -c 'mysql -u$MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE'
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
    me=$(which "$0")
    echo "Downloading new version to /tmp/elabctl"
    curl -sL https://raw.githubusercontent.com/elabftw/elabctl/master/elabctl.sh -o /tmp/elabctl
    chmod -v +x /tmp/elabctl
    mv -v /tmp/elabctl "$me"
}

function start()
{
    is-installed
    docker-compose -f "$CONF_FILE" up -d
}

function status()
{
    is-installed
    docker-compose -f "$CONF_FILE" ps
}

function stop()
{
    is-installed
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

    # remove config file and eventual backup
    if [ -f "${CONF_FILE}.old" ]; then
        rm -vf "${CONF_FILE}.old"
        echo "[x] Deleted ${CONF_FILE}.old"
    fi
    if [ -f "$CONF_FILE" ]; then
        rm -vf "$CONF_FILE"
        echo "[x] Deleted $CONF_FILE"
    fi
    # remove data directory
    if [ -d "$DATA_DIR" ]; then
        sudo rm -rvf "$DATA_DIR"
        echo "[x] Deleted $DATA_DIR"
    fi
    # remove backup dir
    if [ $rmbackup == 'y' ] && [ -d "$BACKUP_DIR" ]; then
        rm -rvf "$BACKUP_DIR"
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
    is-installed
    has-disk-space
    echo "Do you want to make a backup before updating? (y/N)"
    read dobackup
    if [ "$dobackup" = "y" ]; then
        backup
        echo "Backup done, now updating."
    fi
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

# Now we load the configuration file for custom directories set by user
if [ -f /etc/elabctl.conf ]; then
    source /etc/elabctl.conf
    ELABCTL_CONF_FILE="/etc/elabctl.conf"
fi

# elabctl.conf in ~/.config
if [ -f ${HOME}/.config/elabctl.conf ]; then
    source ${HOME}/.config/elabctl.conf
    ELABCTL_CONF_FILE="${HOME}/.config/elabctl.conf"
fi

# if elabctl is in current dir it has top priority
if [ -f elabctl.conf ]; then
    source elabctl.conf
    ELABCTL_CONF_FILE="elabctl.conf"
fi

# check that the path for the data dir is absolute
if [ "${DATA_DIR:0:1}" != "/" ]; then
    echo "Error in config file: DATA_DIR is not an absolute path!"
    echo "Edit elabctl.conf and add a full path to the directory."
    exit 1
fi

# available commands
declare -A commands
for valid in backup bugreport help info infos install logs mysql php-logs self-update start status stop refresh restart uninstall update upgrade usage version
do
    commands[$valid]=1
done

if [[ ${commands[$1]} ]]; then
    # exit if variable isn't set
    set -u
    ascii
    echo "Using elabctl configuration file: "$ELABCTL_CONF_FILE""
    echo "Using elabftw configuration file: "$CONF_FILE""
    echo "---------------------------------------------"
    $1
else
    help
    exit 1
fi
