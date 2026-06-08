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

## Configure pgpool2

### Adjust pgpool.conf in the pgpool2 configuration directory (here /etc/pgpool2/)

![pgpool.conf](./config/pgpool.conf)

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

### Copy and adjust scripts escalation.sh, failover.sh, follow_primary.sh, pgpool_remote_start and reccovery_1st_stage. Directory: /etc/pgpool2/

- ![escalation.sh](./config/escalation.sh)
- ![failover.sh](./config/failover.sh)
- ![follow_primary.sh](./config/follow_primary.sh)
- ![pgpool_remote_start](./config/pgpool_remote_start)
- ![recovery_1st_stage](./config/recovery_1st_stage)

Change ownership of the scripts to user postgres and make them executable.

VERY IMPORTANT: recovery_1st_stage and pgpool_remote_start need to be in the postgres data directory, so that postgres extension pgpool_recovery can find them!!!

```bash
sudo chown postgres:postgres /etc/pgpool2/*.sh /etc/pgpool2/pgpool_remote_start /etc/pgpool2/recovery_1st_stage
sudo chmod +x /etc/pgpool2/*.sh /etc/pgpool2/pgpool_remote_start /etc/pgpool2/recovery_1st_stage
```

Copy script recovery_1st_stage and pgpool_remote_start into the postgres data directory. (/var/lib/postgresql/18/main/)
