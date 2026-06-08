# Install and configure KEA dhcp

## Installation Preparation

### Install additional prerequisit packages

```bash
sudo apt update && sudo apt -y install meson build-essential python3 libbz2-dev libz-dev libicu-dev libboost-all-dev liblog4cplus-dev libkrb5-dev pkg-config
```

### Add the BOOST library paths to root's .bashrc

```script
export BOSST_ROOT=/usr/lib/x86_64-linux-gnu
export LD_LIBARARY_PATH=/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}
export CPLUS_INCLUDE_PATH=/usr/lib/x86_64-linux-gnu:${CPLUS_INCLUDE_PATH}
```

## KEA Installation

### Download and verify KEA source

```bash
mkdir ~/kea-install
cd ~/kea-install
```

```bash
wget https://downloads.isc.org/isc/kea/3.1.9/kea-3.1.9.tar.xz
wget https://downloads.isc.org/isc/kea/3.1.9/kea-3.1.9.tar.xz.asc
wget https://www.isc.org/docs/isc-keyblock.asc
```

- Verify code signing key

```bash
gpg --import isc-keyblock.asc
gpg --verify kea-3.1.9.tar.xz.asc kea-3.1.9.tar.xz
```

- Unpack kea-3.1.9.tar.xz

```bash
tar xvf kea-3.1.9.tar.xz
cd kea-3.1.9/
```

### Build and install KEA

ISC uses meson for the build

```bash
meson setup build -D postgresql=enabled -D krb5=enabled -D crypto=openssl -D buildtype=release
```

Either increase memory of the VM significantly to use meson compile -C build or use ninja -j <max number of cpus> to compile else the compile will fail because of memory exhaution.

```bash
cd build
ninja -j 2
sudo meson install -C build
```

### Create KEA database and user in Postgres

- Set timezone of VM and Postgres to UTC

```bash
sudo timedatectl set-timezone UTC
```

```script
...
timezone = 'UTC'
...
log_timezone = 'UTC'
...
```

#### Create database kea_db

```bash
sudo -u postgres psql -c "CREATE DATABASE kea_db;"
```

#### Cresate database owner kea_admin

```bash
sudo -u postgres psql -c "CREATE USER kea_admin WITH PASSWORD '<password in keepass>';"

sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON kea_db TO kea_admin;"

sudo -u postgres psql kea_db -c "GRANT ALL PRIVILEGES ON public TO kea_admin;"
```

#### Add kea_admin to pg_hba.conf of Postgres to allow scram-sh256-256 login to kea_db

````script
...
hostssl kea_db          kea_admin        127.0.0.0/8             scram-sha-256
hostssl kea_db          kea_admin        10.1.40.1/24             scram-sha-256
hostssl kea_db          kea_admin       2001:1620:53f9:84::1/64   scram-sha-256
hostssl kea_db          kea_admin       fd8a:a5c6:8a3:0::1/64   scram-sha-256
hostssl kea_db          kea_admin        fe80::/8                 scram-sha-256
...

```bash
sudo -u postgres systemctl reload postgresql
````

#### Initialize the databse using kea-admin

```bash
sudo kea-admin db-init pgsql -u kea_admin -p <password from keepass> -n kea_db
```

#### Change synchronous_commit to OFF to improve performance

```bash
sudo -u postgres psql -c "ALTER SYSTEM SET synchronous_commit=OFF;"
```

```

```
