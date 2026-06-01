# Postgresql Installation and configuration

## Install postgresql on the primary and secondary DNS servers

### Automated Repository Configuration for Postgres

```bash
sudo apt update && sudo apt install -y postgresql-common
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
```

### Install postgresql-18

```bash
sudo apt update && sudo apt install postgresql-18
```

### Set the PATH to the binaries for the postgres user in .bashrc

```script
PATH=/usr/lib/postgresql/18/bin/:${PATH}
```

### cleaup /var/lib/postgresql/18/main and initialize the cluster DB

```bash
sudo systemctl stop postgresql
sudo rm -rf /var/lib/postgresql/18/main/*
sudo su - postgres initdb -D /var/lib/postgresql/18/main/
sudo systemctl start postgres
```

Status can be checked in the syslog for services postgresql and postgresql@18-main

```bash
sudo systemctl status postgresql@18-main
sudo journalctl -xeu postgresql@18-main
```

### CHange ownership of /var/backups/postgres/ and /var/archive/

```bash
sudo chown -R postgres:postgres /var/archive/
sudo chown -R postgres:postgres /var/backups/postgresql/
```

## Postgres Configuration on the Primary Instance (b100udns3)

### Create and sign the common ssl key

- Create the private key and provide access to postgres

```bash
sudo openssl genrsa -out /etc/ssl/private/pg-kea-dhcp.key.pem 4096
sudo chown :ssl-cert /etc/ssl/private/pg-kea-dhcp.key.pem
sudo chmod g+r /etc/ssl/private/pg-kea-dhcp.key.pem
```

- Create the certificate signing request

```bash
sudo mkdir /etc/ssl/csr/
sudo openssl req -new -sha256 -key /etc/ssl/private/pg-kea-dhcp.key.pem \
    -out /etc/ssl/csr/pg-kea-dhcp.csr.pem \
    -subj "/C=CH/ST=Basel-Stadt/L=Basel/O=HCInfoTech, LLC./OU=DNS/CN=b100udns-lb.mgt.int.hcinfotech.ch"
    -addext "subjectAltName = DNS:b100udns3.mgt.int.hcinfotech.ch, \
                              DNS:b100udns5.mgt.int.hcinfotech.ch, \
                              DNS:b100udns-lb.mgt.int.hcinfotech.ch, \
                              IP:10.1.40.83, \
                              IP:10.1.40.84, \
                              IP:10.1.40.85, \
                              IP:10.1.40.113"
```

- Sign the csr in b100u006 and copy the signed cert into /etc/ssl/certs/

```bash
scp 10.1.10.36:/opt/openssl/intermediate-ca/certs/pg-kea-dhcp.cert.pem /etc/ssl/certs/
```

### Configure postgres in postgresql.conf and hb_pga.conf

![postgresql.conf](./config/postgresql.conf)
![pg_hba.conf](./config/pg_hba.conf)
![recovery.conf](./config/recovery.conf)

#### Primary instance b100udns3

1. Create a password for user postgres

```bash
sudo -u postgres psql -c "alter user postgres  with password '<password from keepass>';"
```

2. Create the replicationuser grantingnlogin and replication

```bash
sudo -u postgres psql -c "create user replicationuser with password '<password from keepass>';"
sudo -u postgres psql -c "alter role replicationuser with replication login;"
```

3. Create file /var/lib/postgresql/.pgpass containing the passwords of postgres and replicationuser

```bash
sudo -u postgres nvim /var/lib/postgresql/.pgpass
```

```script
*:*:*:postgres:<password>
*:*:*:replicationuser:<password>
```

```bash
sudo -u postgres chmod go-rwx /var/lib/postgresql/.pgpass
```

4. Create the replication slots

```bash
sudo -u postgres psql -c "SELECT * FROM pg_create_physical_replication_slot('b100udns3');"
sudo -u postgres psql -c "SELECT * FROM pg_create_physical_replication_slot('b100udns4');"
sudo -u postgres psql -c "SELECT * FROM pg_create_physical_replication_slot('b100udns5');"
```

```bash
sudo -u postgres psql -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;"
```

5. Validate password-less login for replicationuser

```bash
sudo -u psql postgres replicationuser
```

#### Secondary instances b100udns4 and b100udns5

1. Copy the configuration files from the primary instance

```bash
sudo ssh b100udns3 cat /etc/postgresql/18/main/postgresql.conf|sudo -u postgres tee /etc/postgresql/18/main/postgresql.conf
sudo ssh b100udns3 cat /etc/postgresql/18/main/pg_hba.conf|sudo -u postgres tee /etc/postgresql/18/main/pg_hba.conf
sudo ssh b100udns3 cat /etc/postgresql/18/main/pg_ident.conf|sudo -u postgres tee /etc/postgresql/18/main/pg_ident.conf
sudo ssh b100udns3 cat /etc/postgresql/18/main/conf.d/recovery.conf|sudo -u postgres tee /etc/postgresql/18/main/conf.d/recovery.conf
sudo ssh b100udns3 cat /var/lib/postgresql/.pgpass|sudo -u postgres tee /var/lib/postgresql/.pgpass

sudo -u postgres chmod go-rwx /var/lib/postgresql/.pgpass
```

2. Change file /etc/postgresql/18/main/reovery.conf to reflect the correct server and replication slot

3. Stop Postgres and remove the content from the data directory

```bash
sudo systemctl stop postgresql
```

```bash
sudo -u postgres rm -rf /var/lib/postgresql/18/main/*
```

4. Perform the base backup from the primary instance to seat the replication

```bash
sudo -u postgres pg_basebackup -D /var/lib/postgresql/18/main/ \
    --write-recovery-conf --wal-method=stream \
    --slot=<replication slot for this instance> \
    --verbose --host=b100udns3 --username=replicationuser --no-password
```

5. Restart poastgresql and check the logfile

```bash
sudo systemctl restart postgresql
```

```bash
sudo systemctl status postgresql@18-main
sudo journalctl -xeu postgresql@18-main
```
