![HCInfoTech Banner](../../common/images/dns-infrastructure-setup-banner.png)

# New DNS infrastructure setup

## DNS Landscape

### VMs used

- b100udns1 - primary nameserver - (Proxmox node 1)
- b100udns2 - secondary nameserver - (Proxmox node 2)
- b100udns3 - secondary nameserver - (Proxmox node 3)

VMs using Ubuntu 25.04 (plucky puffin) with full disk encryption at rest

## Installation and configuration

### Install BIND9

Standard Ubuntu/Debian bind9 package used. To install:

```bash
sudo apt update && sudo apt install -y bind9
```

### BIND9 Configuration

Default configuration directory /etc/bind/. Standard files to be updated or created:

- named.conf
- named.local.options
- named.conf.local

#### Configuration of a primary nameserver

- named.conf

If configuring the server for dynamic updates or restricted zone transfers follow the steps as outline in
![Dynamic DNS Setup](../reconf-ddns-current-setup/README.md)

named.conf requires an include statement to reference the ddns-signature file

```bash
include "/etc/bind/ddns-signature"        # file containing the key stanzas created by tsig-keygen
```

- named.conf.options

Add an Access Control List (acl) stanza restricting access to specific networks or IP addresses. Unless there are other measures
in place to restrict communication, access should be restricted to internal networks to prevent spoofing and DoS attacks.

```bash
acl internal {
  192.168.1.0/24;
  10.5.20.0/24;
};
```

⚠️Don’t forget semicolons, missing them is a common error.

Add forwarders section to the options stanza. All queries fo unknown zones will be handed of to the forwardes.

```bash
forwarders {
  8.8.8.8;        # Google DNS as an example
  1.1.1.1;        # CloudFlare
};
```

Add the allow-query option to one of the configured acl. (e.g. internal)

```bash
allow-quesry { internal; };
```

Add the IP addresses of the secondary nameservers to the allow-notify and allow-transfer sextions in the opton stanza

```bash
allow-notify {
  192.168.1.35;       # first secondary nameserver
  192.168.5.68;       # second secondary nameserver
};
```

```bash
allow-transfer {
  192.168.1.35;       # first secondary nameserver
  192.168.5.68;       # second secondary nameserver
};
```

```bash
notify yes;
recursion yes;
```

![sample named.conf.options here](./config/primary-dns/sample.named.conf.options)

- named.conf.local

This file containes entries for the managed zones.

For each zone for which this nameserver is authorative enter the following stanza:

```bash
zone "example.com" IN {
    type primary;
    file "/var/lib/bind/example.com.zone";        # in case dynamic update is configured the i
                                                  # zone file needs to be in /var/lib/bind, else it
                                                  # can be created in /etc/bind
    allow-transfer {
      192.168.1.35;                               # secondary nameservers
      192.168.1.68;
      key ddns-transfer-key;                      # required if transfer is protectd by TSIG, eles ommit
    };
    update-policy {                               #required if dynamic updates are cionfigured, else ommit
      grant ddns-update-key zonesub ANY;
    };
};
```

Follow the format documented for a [secondary nameserver](#configuration-of-a-secondary-nameserver)

![sample named.conf.local here](./config/primary-dns/sample.named.conf.local)

- Configuration validation

Execute named-checkconf and named-checkzone commands to validate.

```bash
sudo named-checkconf
sudo named-checkzone a.example.com /etc/bind/a.example.conf.zone
```

- Start named service and validate status and logs

```bash
sudo systemctl start named
```

```bash
systemctl status named

sudo journalctl -eu named
```

#### Configuration of a secondary nameserver

- named.conf

Create a file containing the transfer key and the stanza for the primary requesting the key. (e.g. ddns-signature)

```bash
key "ddns-transfer-key" {           # TSIG key name
        algorithm hmac-sha512;      # TSIG algorithm
        secret "xxxxx...";          # TSIG password
};
server 192.168.1.20 {               # IP address of primary nameserver
  keys {
    ddns-transfer-key;              # references transfer key from stanza above
  };
};
```

Change ownership and permissions of the file. This needs to be accessible only to the named process.

```bash
chwon root:bind /etc/bind/ddns-signature
chmod g+r,o-rwx /etc/bind/ddns-signature
```

Add tn include statement for the file to named.conf

```bash
...
include "/etc/bind/ddns-signatures"
```

- named.conf.options

Add an Access Control List (acl) stanza restricting access to specific networks or IP addresses. Unless there are other measures
in place to restrict communication, access should be restricted to internal networks to prevent spoofing and DoS attacks.

```bash
acl internal {
  192.168.1.0/24;
  10.5.20.0/24;
};
```

⚠️Don’t forget semicolons, missing them is a common error.

Add forwarders section to the options stanza. All queries fo unknown zones will be handed of to the forwardes.

```bash
forwarders {
  8.8.8.8;        # Google DNS as an example
  1.1.1.1;        # CloudFlare
};
```

Add the allow-query option to one of the configured acl. (e.g. internal)

```bash
allow-quesry { internal; };
```

![sample named.conf.options here](./config/secondary-dns/sample.named.conf.options)

- named.conf.local

Add the zones for which this DNS server is secondary to named.conf.local

```bash
zone "example.com" IN {                   # zone example.com
  type secondary;
  file "/var/lib/bind/example.com.zone";  # location of the transferred zone file
  primaries {
      192.168.1.20;                       # IP address of the authorative nameserver for the zone
  };
};
```

⚠️The zone file needs to be located in /vart/lib/bind. AppArmor prevents named form updating files in /etc/bind

![sample named.conf.local here](./config/secondary-dns/sample.named.conf.local)

- Configuration validation

Execute named-checkconf command to validate.

```bash
sudo named-checkconf
```

- Start named service and validate status and logs

```bash
sudo systemctl start named
```

```bash
systemctl status named

sudo journalctl -eu named
```
