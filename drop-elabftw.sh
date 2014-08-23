#!/bin/sh
# http://www.elabftw.net

# display ascii logo
clear
echo ""
echo "  ___ | |  ____ | |__   / _|| |_ __      __"
echo " / _ \| | / _ ||| |_ \ | |_ | __|\ \ /\ / /"
echo "|  __/| || (_| || |_) ||  _|| |_  \ V  V / "
echo " \___||_| \__,_||_.__/ |_|   \__|  \_/\_/  "
echo ""

logfile='elabftw.log'
echo "You can follow the status of the install with"
echo "tail -f $logfile (in another terminal)"
echo ""

echo "[*] Installing nginx, php, openssl and git"
apt-get update >> $logfile 2>&1
#apt-get upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y install \
    nginx \
    openssl \
    php5-fpm \
    php5-mysql\
    php-apc \
    php5-gd \
    php5-curl \
    python-setuptools \
    curl \
    git \
    software-properties-common >> $logfile 2>&1

# we need the latest version of mariadb (or mysql 5.6)
echo "[*] Installing mariadb version 10.0 (SQL server)"
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db >> $logfile 2>&1
add-apt-repository 'deb http://nwps.ws/pub/mariadb/repo/10.0/ubuntu trusty main' >> $logfile 2>&1
apt-get update >> $logfile 2>&1
DEBIAN_FRONTEND=noninteractive apt-get -y install mariadb-server >> $logfile 2>&1

echo "[*] Configuring server"
# mysql config
sed -i -e"s/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/my.cnf

# nginx config
sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf
sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf
echo "daemon on;" >> /etc/nginx/nginx.conf

# php-fpm config
sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php5/fpm/php.ini
sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php5/fpm/php-fpm.conf
sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php5/fpm/pool.d/www.conf

# nginx site conf
wget -qO /etc/nginx/sites-available/default https://raw.githubusercontent.com/NicolasCARPi/drop-elabftw/master/nginx-site.conf
# ssl key + cert
wget -qO /etc/ssl/certs/server.key https://raw.githubusercontent.com/NicolasCARPi/drop-elabftw/master/server.key
wget -qO /etc/ssl/certs/server.crt https://raw.githubusercontent.com/NicolasCARPi/drop-elabftw/master/server.crt

echo "[*] Installing elabftw in /elabftw"
# elabftw
git clone --depth 1 -b next https://github.com/NicolasCARPi/elabftw.git /elabftw >> $logfile 2>&1
# fix permissions
chown -R www-data:www-data /elabftw


echo "[*] Starting php5"
service php5-fpm start
echo "[*] Starting nginx web server"
service nginx start
# because it is started already with wrong default conf
service nginx restart
echo "[*] Starting mysql database"
service mysql start

# create the elabftw database
rootpass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
echo "[*] Giving a password to MySQL root account"
echo "UPDATE mysql.user SET Password=PASSWORD('$rootpass') WHERE User='root';
FLUSH PRIVILEGES;" | mysql -u root
# now we put the password in the config file
sed -i "/\[client\]/a user = root \\npassword = $rootpass" /etc/mysql/my.cnf

echo "[*] Creating the  elabftw database and user with random password"
echo "create database elabftw;" | mysql -u root -p$rootpass
pass=$(tr -dc A-Za-z0-9 < /dev/urandom | head -c 12 | xargs)
echo "grant usage on *.* to elabftw@localhost identified by '$pass';" | mysql -u root -p$rootpass
echo "grant all privileges on elabftw.* to elabftw@localhost;" | mysql -u root -p$rootpass
mysql -u root -p$rootpass elabftw < /elabftw/install/elabftw.sql

ip=$(curl -s http://ifconfig.me)
echo "Congratulations! eLabFTW is now running :)\n
====> Go to https://$ip/install now ! <====\n
MySQL hostname : localhost\n
MySQL Database : elabftw\n
MySQL login : elabftw\n
MySQL password : $pass\n
====> Go to https://$ip/install now ! <====\n
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "\n\n\nPassword for MySQL user 'elabftw' : $pass" >> $logfile
echo "Password for MySQL user 'root': $rootpass" >> $logfile
echo "The password is also stored in the log file $logfile"
echo "Please report bugs you find. ENJOY ! :)"
exit 0
