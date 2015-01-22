# drop-elabftw

Get [eLabFTW](http://www.elabftw.net) installed and running in no time on a drop !

The following actions will be performed :

- install of nginx (web server)
- install of  mariadb (sql server)
- install of elabftw
- get everything up and running

**WARNING**: this script will work for a fresh drop. If you already have a server running, you should consider a [normal install](https://github.com/NicolasCARPi/elabftw#install-on-a-gnulinux-server) instead.

# How to use

* Create an account on [DigitalOcean](https://cloud.digitalocean.com/registrations/new)

* Create a droplet with Ubuntu 14.04 x64 (works also with 14.10)

* Open a terminal and SSH to your droplet (the root password is in your mailbox)

~~~
ssh root@12.34.56.78
~~~

* Go inside a tmux session

~~~
tmux
~~~

* Enter the following command

```
wget -qO- http://get.elabftw.net|sh
```

* (Optional) Open a new pane with Ctrl-b, release and press %. Then enter :

~~~
tail -f elabftw.log
~~~

* Read what is displayed at the end

ENJOY ! :D
