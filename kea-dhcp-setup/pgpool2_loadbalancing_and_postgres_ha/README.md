# pgpool2 installation and configuration

## Install pgpool2 on all three KEA mgt instances

### Install pgpool2 on Ubuntu

#### Install prerequiaits

```bash
sudo apt update && sudo apt -y install autoconf libtool libldap2-dev libpam-dev libpq-dev libcrypt-dev postgresql-server-dev-18
```

#### Download and unpack pgpool-II-4.7.1.tar.gz

```bash
cd ~
wget https://www.pgpool.net/source/pgpool-II-4.7.1.tar.gz
tar xzvf pgpool-II-4.7.1.tar.gz
```

#### Configure, make and make install of pgpool2

```bash
cd ~/pgpool-II-4.7.1/
autoreconf -fi

./configure --with-openssl --with-pam --with-ldap
make

sudo make install
```

#### Install pgpool_recovery extension into postgres

```bash
cd ~/pgpool-II-4.7.1/src/sql/pgpool-recovery/
make
sudo make install
```

Connect to postgres (primary instance) and create the pgpool_recovery extension

```bash
sudo -u postgres psql -c 'CREATE EXTENSION pgpool_recovery;'
```

Add pgpool.pg_ctl = '/usr/lib/postgresql/18/bin/pg_ctl' (location od pg_ctl) to postgresql.conf

```script
...
pgpool.pg_ctl = '/usr/lib/postgresql/18/bin/pg_ctl'
```

Reload postgresql

```bash
sudo systemctl reload postgresql
```

### Install arping required for watchdog

```bash
sudo apt update && sudo apt -y install arping
```

Install socat (filan - used in failover scripts)

```bash
sudo apt update && sudo apt -y install socat
```

### Create user pgpool in the database with role pg_monitor

```bash
sudo -u postgres psql -c "create user pgpool with login password '<password from keepass>';"
sudo -u postgres psql -c "grant pg_monitor to pgpool;"
```

### Create the pgpool user md5 password and store it in /etc/pgpool2/pcp.conf

```bash
pg_md5 -p
```

NOTE: Password from keepass

### Create the AES encrypted passwords for postgres and pgpool and store them in pool_passwd

- Create file .poolkey in the home directory of user postgres (gnerated random string from keepass)

```bash
chmod go-rwx /var/lib/postgresql/.poolkey
```

- Use pg_enc to create the AES encrypted passwords

```bash
pg_enc -m -f /etc/pgpool2/pgpool.conf -u pgpool -p
pg_enc -m -f /etc/pgpool2/pgpool.conf -u postgres -p
```

### Change ownership and permissions of /etc/pgpool2/ and /etc/pgpool2/pcp.conf

```bash
sudo chown -R :postgres /etc/pgpool2
sudo chmod o-rwx pcp.conf
```
