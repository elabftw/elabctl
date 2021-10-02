# Changelog for elabctl

## Version 2.3.0

* Use `docker compose` instead of `docker-compose` command
* Add a warning with a choice to continue update if the latest version is a beta version

## Version 2.2.4
* Fix ENABLE_LETSENCRYPT being incorrectly set to true for self signed certs (#20)
* Drop "no domain name" support

## Version 2.2.3
* Fix permissions for uploaded files folder chown command

## Version 2.2.2
* Use correct mysql container name for backup

## Version 2.2.1
* Add link to latest version changelog after update

## Version 2.2.0
* Replace php-logs with access-logs and error-logs using docker logs command

## Version 2.1.1
* Fix wrongly committed local config

## Version 2.1.0
* Allow specifying the name of the containers in config file

## Version 2.0.1
* Add --no-tablespaces argument to mysqldump to avoid PROCESS privilege error

## Version 2.0.0

* Get a pre-processed config file from get.elabftw.net
* Don't install certbot or try to get a certificate
* Suppress the MySQL warning. Allow silent backup for cron with > /dev/null
* Add mysql-backup command to just make a dump of the database, don't zip the files

## Version 1.0.4

* Use restart instead of refresh for update command (see elabftw/elabftw#1543)

## Version 1.0.3

* Use refresh instead of restart for update command
* Use certbot instead of letsencrypt-auto

## Version 1.0.2

* Fix bugreport hanging on elabftw version
* Add mysql command to spawn mysql shell in container
* Check for disk space before update (#15)

## Version 1.0.1

* Download conf file to /tmp to avoid permissions issues
* Add sudo for mkdir
* Open port 80 for Let's Encrypt
* Use sudo to remove data dir
* Log file is gone
* Don't try to install stuff, let user deal with it
* Script can be used without being root

## Version 0.6.4

* Fix install on CentOS (thanks @M4aurice) (#14)
* Ask before doing backup

## Version 0.2.2

* Fix install on RHEL (thanks @folf) (#7)
* Fix running backup from cron (#6)
* Use chmod 600 not 700 for config file
* Allow traffic on port 443 with ufw
* Add GPLv3 licence
* Add CHANGELOG.md
