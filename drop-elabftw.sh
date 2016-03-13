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

# get info for letsencrypt and nginx
echo "[:)] Welcome to the install of elabftw!"
echo ""
echo "[?] What is the domain name of this server?"
echo "[!] WARNING: don't put the IP address!"
echo "[*] Example : elabftw.ktu.edu"
read -p "[?] Your domain name: " domain
echo "[?] Second and last question, what is your email?"
echo "[!] It is sent only to letsencrypt"
read -p "[?] Your email: " email
echo "[*] You can follow the status of the install with"
echo "[*] Do Ctrl-b, release and press '%'"
echo "[$] tail -f $logfile"
echo ""

echo "[*] Installing nginx, php, mysql, openssl and git"

logfile='elabftw.log'
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

# nginx site conf
service nginx stop
wget -qO /etc/nginx/sites-available/default https://raw.githubusercontent.com/elabftw/drop-elabftw/master/nginx-site.conf
sed -i "s/DOMAIN/$domain/g" /etc/nginx/sites-available/default
# get letsencrypt
git clone --depth 1 -b master https://github.com/letsencrypt/letsencrypt /letsencrypt >> $logfile 2>&1
cd /letsencrypt && ./letsencrypt-auto certonly --email $email --agree-tos -d $domain

echo "[*] Installing elabftw in /elabftw"
# elabftw
git clone --depth 1 -b master https://github.com/elabftw/elabftw.git /elabftw >> $logfile 2>&1
# fix permissions
chown -R www-data:www-data /elabftw

# create the elabftw database
echo "[*] Starting MySQL database"
service mysql start
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

echo "[*] Starting php-fpm"
service php5-fpm start
echo "[*] Starting nginx"
service nginx start

ip=$(dig +short myip.opendns.com @resolver1.opendns.com)
echo "Here are the credentials for your eLabFTW installation:\n
Host for mysql database : localhost\n
Name of the database : elabftw\n
Username to connect to MySQL server : elabftw\n
Password : $pass\n
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%"
echo "\n\n\nPassword for MySQL user 'elabftw' : $pass" >> $logfile
echo "Password for MySQL user 'root': $rootpass" >> $logfile
echo "The password is also stored in the log file $logfile"
echo "Now you need to get a certificate from letsencrypt and start nginx"
