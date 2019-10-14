# Changelog for elabctl

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
