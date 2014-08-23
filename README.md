# drop-elabftw

Get eLabFTW installed and running in no time on a drop !

The following actions will be performed :

- install of nginx (web server)
- install of  mariadb (sql server)
- install of elabftw.
- get everything up and running

# How to use

* Create an account on [DigitalOcean](https://cloud.digitalocean.com/registrations/new)

* Create a droplet with Ubuntu 14.04 x64

* SSH to your droplet (the root password is in your mailbox)

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
