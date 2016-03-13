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

echo "[*] Installing nginx, php, mysql, openssl and git"
apt-get update >> $logfile 2>&1
#apt-get upgrade
DEBIAN_FRONTEND=noninteractive apt-get -y install \
    nginx \
    mysql-server \
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

echo "[*] Configuring server"
# mysql config
sed -i -e"s/^bind-address\s*=\s*127.0.0.1/bind-address = 0.0.0.0/" /etc/mysql/my.cnf

# nginx config
sed -i -e"s/keepalive_timeout\s*65/keepalive_timeout 2/" /etc/nginx/nginx.conf
sed -i -e"s/keepalive_timeout 2/keepalive_timeout 2;\n\tclient_max_body_size 100m/" /etc/nginx/nginx.conf

# php-fpm config
sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" /etc/php5/fpm/php.ini
sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 100M/g" /etc/php5/fpm/php.ini
sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /etc/php5/fpm/php-fpm.conf
sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" /etc/php5/fpm/pool.d/www.conf

# nginx site conf
wget -qO /etc/nginx/sites-available/default https://raw.githubusercontent.com/elabftw/drop-elabftw/master/nginx-site.conf
# ssl key + cert
if [ ! -f /etc/ssl/certs/server.crt ]; then
    openssl req \
        -new \
        -newkey rsa:4096 \
        -days 9999 \
        -nodes \
        -x509 \
        -subj "/C=FR/ST=France/L=Paris/O=elabftw/CN=www.example.com" \
        -keyout /etc/ssl/certs/server.key \
        -out /etc/ssl/certs/server.crt
fi

echo "[*] Installing elabftw in /elabftw"
# elabftw
git clone --depth 1 -b master https://github.com/elabftw/elabftw.git /elabftw >> $logfile 2>&1
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

ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
echo "Congratulations! eLabFTW is now running :)\n
====> Go to https://$ip/install now ! <====\n
Host for mysql database : localhost\n
Name of the database : elabftw\n
Username to connect to MySQL server : elabftw\n
Password : $pass\n
====> Go to https://$ip/install now ! <====\n
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "\n\n\nPassword for MySQL user 'elabftw' : $pass" >> $logfile
echo "Password for MySQL user 'root': $rootpass" >> $logfile
echo "The password is also stored in the log file $logfile"
echo "Please report bugs you find. ENJOY ! :)"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "It is highly recommended to use Let'sEncrypt project to get a real certificate."
echo "https://github.com/letsencrypt/letsencrypt"
echo "The one you have here is autosigned and users will get warnings."
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
