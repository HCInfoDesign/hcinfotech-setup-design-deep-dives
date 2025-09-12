![HCInfoTech Banner](../../common/images/DDNS-GitHub-Banner.png)

# Network Reconfiguration: Dynamic DNS and TSIG

This repository documents the reconfiguration of a Proxmox-based lab network to simulate a cloud-provider-like environment.  
The first step comprises enabling **secure Dynamic DNS** by using **TSIG keys** for authenticated zone transfers and updates.

---

## 1. Current compared to target configuration

### Current setup

- 3-node Proxmox cluster (HP Proliant DL360 Gen8)
- 1 standalone Proxmox node simulating a distant region
- Unmanaged switch, bonded NIC pairs
- IPv4 only

[Current Network](../../common/images/network-current-diagram.png)

---

### Target setup

- Same Proxmox nodes
- Managed switches with VLAN support
- OPNSense router/firewall for VLAN separation and routing
- IPv6 for internal addressing
- Dynamic DNS with TSIG authentication

[Target Network](../../common/images/network-to-be-diagram.png)

---

## 2. Dynamic DNS setup

### Generate TSIG keys

````bash
# Zone Transfer Key
tsig-keygen -a hmac-sha512 ddns-transfer-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1

# Zone Update Key
tsig-keygen -a hmac-sha512 ddns-update-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1

Set correct ownership and permissions:

```bash
sudo chown root:bind /etc/bind/ddns-signatures
sudo chmod g-w,o-rwx /etc/bind/ddns-signatures
````

Store keys securely in a password manager or Vault.

- Zone transfers → require ddns-transfer-key
- Dynamic updates → require ddns-update-key

---

## 3. Configure bind

Include the TSIG keys in /etc/bind/named.conf:

```bash
include "/etc/bind/ddns-signatures";
```

Require signed zone transfers:

```bash
allow-transfer {
    192.0.2.10;      # example secondary DNS
    key ddns-transfer-key;
};
```

⚠️ Don’t forget semicolons, missing them causes a common error.

Restart bind:

```bash
sudo systemctl restart named
```

---

## 4. Zone Transfers with dig

Create a shell alias to load credentials without exposing them in the shell history:

```bash
alias set_HMAC='read -i "hmac-sha512 " -ep "Encrypt. Algorithm: " HMAC_ALG; \
read -i "ddns-update-key " -ep "DDNS User: " HMAC_USER; \
read -sep "DDNS Password: " HMAC_PASSWD; \
HMAC=\${HMAC_ALG}:\${HMAC_USER}:\${HMAC_PASSWD}'
```

Use the exported variable $HMAC with dig and nsupdate.

Example zone transfer:

```bash
dig @ns1.in.hcinfotech.ch +noall +answer in.hcinfotech.ch -y $HMAC -t AXFR \
| grep -E $'[\t| ](A|CNAME|MX)[\t| ]'
```

Explanation:

- Connects to the primary nameserver for zone in.hcinfotech.ch
- Initiates an authenticated AXFR zone transfer
- Filters for A, CNAME, and MX records

---

## 5. Configure the secondary name servers to use the same key for transfers

Securely copy file /etc/bind/ddns-signatures to the secondary DNS servers

Add a section indicating the primary name server after the transfer key in file /etc/bind/ddns-signatures

```bash
key "ddns-transfer-key" {
    algorithm hmac-sha512;
    isecret "XXXX";
};
server 192.168.1.20 {   # example ip of primary name server
    keys {
        ddns-transfer-key;
    };
};
```

You can delete key ddns-update-key from the file on the secondary nameserver.

Restart named on secondary

```bash
sudo systemctl restart named
```

---

## 6. Configure the primary nameserver for dynamic updates

Update /etc/bind/named.conf.local on the primary name server and add the following section
to any zone prepared for dynamical update:

```bash
update-policy {
 grant ddns-update-key zonesub ANY;
};
```

AppArmor prevents named from updating files in /etc/bind. The zone file needs to be stashed in
directory /var/lib/bind/ in order for it to be updated by named.

Example zone entry in /etc/bind/named.conf.local:

```bash
zone "example.com" IN {
  type primary;
  file "/var/lib/bind/example.com.zone";
  allow-transfer {
    192.168.0.20;    # example secondary name server
  };
  update-policy {
    grant ddns-update-key zonesub ANY;
  };
};
```

Create the initial zone file in /var/lib/bind/. The zone file needs to contain the SOA record,
and the NS records of the name servers. nsupdate loads everything else dynamically.

Example initial zone file /var/lib/bind/example.com.zone:

```bash
$TTL 172800     ; 2 days
$ORIGIN example.com.
@                 IN SOA  ns1.example.com. info.example.com. (
                                2025091000 ; serial
                                43200      ; refresh (12 hours)
                                900        ; retry (15 minutes)
                                1814400    ; expire (3 weeks)
                                7200       ; minimum (2 hours)
                                )
;NAME       TTL   CLASS   TYPE    Resource Record
                  IN      NS      ns1.example.com

;Name Servers
ns1               IN      A       192.168.1.20
```

---

## 7. Transfer the currently existing zone to the new dynamic zone

Use dig to create the transfer file, after executing set_MAC alias to create the $HMAC variable

```bash
dig @ns1.example.com +noall +answer example.com -y \$HMAC -t AXFR \
| grep -E $'[\t| ](A|CNAME|MX)[\t| ]' > ~/example.com.zone.transfer
```

Add all the record types in your zone that need to be transferred. You can cleanup all the unwanted entries now,
if so desired.

Add "update add " in front of every line. For example in vim with:

```bash
:%s/^/update add /
```

Add the following two lines as the first two lines of the file

```bash
server ns1.example.com
zone example.com
```

Add the following as the last line of the file:

```bash
send
```

Use nsupdate to create the new zone

```bash
nsupdate -y $HMAC ~/example.com.zone.transfer
```

This updates all the records of the file into the new zone. It creates a journal file
example.com.zone.jnl in /var/lib/bind and it notifies all the secondary name servers of
the changed zone.

Manage this zone only with nsupdate, as manually changing the zone
file causes conflicts and inconsistencies.

## 8. Dynamic updates with nsupdate

### Add a record

update.txt:

```bash
server ns1.example.com
zone example.com
update add test.example.com. 3600 IN AAAA 2001:db8::1234
send
```

Run:

```bash
nsupdate -y $HMAC update.txt
```

### Delete a record

update.txt:

```bash
server ns1.example.com
zone example.com
update delete test.example.com. IN AAAA
send
```

Run:

```bash
nsupdate -y $HMAC update.txt
```

Verify:

```bash
dig @ns1.example.com test.example.com AAAA
```

I'm temporarily using the following API [bind-rest-api](https://gitlab.com/jaytuck/bind-rest-api.git), based on dnspython. It serves as a start,
but it needs work in part of the capability and with security.

---

## 9. Security best practices

🔑 Key Management

- Rotate keys regularly
- Separate keys for transfer compared to update
- Revoke unused keys immediately
- Store keys in Vault or KeePass

🔒 Access Control

- Restrict allow-transfer and allow-update to trusted IPs and keys
- Avoid using shared update keys across clients

🧩 Operational Hardening

- Run named as a non-privileged user
- Restrict key file permissions (640)
- Disable dynamic updates on static zones

📜 Logging and Auditing

- Enable query/update logging in bind
- Periodically review logs for anomalies
- Optionally integrate with Security Information and Event Management (SIEM)

🧪 Testing

- Always validate updates with dig
- Test failure cases (wrong key, expired TTL, etc.)

---

## 10. Next steps

This Dynamic DNS configuration is the foundation for broader reconfiguration:

1. Migrate to IPv6 – replace IPv4 addressing with IPv6
2. Introduce Managed Switches – VLAN support for tenant/service isolation
3. Deploy OPNSense – central routing, firewalling, VLAN separation
4. Adopt Software-Defined Networking (SDN) principles – prepare for multitenant cloud simulation

I document each step in follow-up guides and YouTube walk-throughs.
