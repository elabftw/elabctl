# This repo has moved!

This script has been included in [main eLabFTW repository](https://github.com/elabftw/elabftw).

# elabctl.sh

This script is used to manage an eLabFTW instance.

#### See the main [documentation](https://doc.elabftw.net).

## Install

As root:

With `curl`:

~~~bash
curl -sL https://get.elabftw.net -o /usr/local/bin/elabctl && chmod +x /usr/local/bin/elabctl
~~~

Or with `wget`:

~~~bash
wget -qO- https://get.elabftw.net > /usr/local/bin/elabctl && chmod +x /usr/local/bin/elabctl
~~~

## Use

Make sure that `/usr/local/bin` is in your `$PATH`.

~~~bash
elabctl help
~~~
