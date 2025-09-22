![HCInfoTech Banner](../../common/images/DDNS-GitHub-Banner.png)

# Network Reconfiguration: Dynamic DNS and TSIG

## 1. Dynamic DNS setup

### Generate TSIG keys

```bash
# Zone Transfer Key
tsig-keygen -a hmac-sha512 ddns-transfer-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1

# Zone Update Key
tsig-keygen -a hmac-sha512 ddns-update-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1
```

Set correct ownership and permissions:

```bash
sudo chown root:bind /etc/bind/ddns-signatures
sudo chmod g-w,o-rwx /etc/bind/ddns-signatures
```

Store keys securely in a password manager or Vault.

- Zone transfers → require ddns-transfer-key
- Dynamic updates → require ddns-update-key

## Example: [Primary ddns-signatures file](./config/primary-dns/ddns-signatures)

## 2. Configure bind

Include the TSIG keys in /etc/bind/named.conf:

```conf
include "/etc/bind/ddns-signatures";
```

Example: [primary named.conf](./config/primary-dns/named.conf)

Require signed zone transfers in namde.conf.options:

```conf
allow-transfer {
    10.1.51.82;      # example secondary DNS
    key ddns-transfer-key;
};
```

Example: [primary named.conf.options](./config/primary-dns/named.conf.options)

⚠️ Don’t forget semicolons, missing them causes a common error.

Restart bind:

```bash
sudo systemctl restart named
```

---

## 3. Zone Transfers with dig

Create a shell alias to load credentials without exposing them in the shell history:

```code
alias set_HMAC='read -i "hmac-sha512 " -ep "Encrypt. Algorithm: " HMAC_ALG; \
read -i "ddns-update-key " -ep "DDNS User: " HMAC_USER; \
read -sep "DDNS Password: " HMAC_PASSWD; \
HMAC=${HMAC_ALG}:${HMAC_USER}:${HMAC_PASSWD}'
```

Use the exported variable $HMAC with dig and nsupdate.

Example zone transfer:

```bash
dig @ns1.a.internal.hcinfotech.ch +noall +answer a.internal.hcinfotech.ch -y $HMAC -t AXFR \
| grep -E $'[\t| ](A|CNAME|MX)[\t| ]'
```

Explanation:

- Connects to the primary nameserver for zone a.internal.hcinfotech.ch
- Initiates an authenticated AXFR zone transfer
- Filters for A, CNAME, and MX records

---

## 4. Configure the secondary name servers to use the same key for transfers

Securely copy file /etc/bind/ddns-signatures to the secondary DNS servers

Add a section indicating the primary name server after the transfer key in file /etc/bind/ddns-signatures

```conf
key "ddns-transfer-key" {
    algorithm hmac-sha512;
    secret "Alongandverysecretassphrase";
};
server 10.1.51.81 {   # example ip of primary name server
    keys {
        ddns-transfer-key;
    };
};
```

You can delete key ddns-update-key from the file on the secondary nameserver.

Example: [secondary ddns-signatures file](./config/secondary-dns/ddns-signatures)

Update /etc/bind/named.conf to include ddns-signature file.

```conf
...
include "/etc/bind/ddns-signatures";
```

Example: [secondary named.conf](./config/secondary-dns/named.conf)

Add the key to allow-transfer in /etc/bind/named.conf.options

```conf
allow-transfer {
    ...
    key ddns-transfer-key;
};
```

Example: [secondry named.conf.options](./config/secondary-dns/named.conf.options)

Restart named on secondary

```bash
sudo systemctl restart named
```

---

## 5. Configure the primary nameserver for dynamic updates

### 5.1 Prepare the transfer of the zones

- Freeze the updates of the zones until the setup is completed.

- Copy the zonefiles from /etc/bind to /var/lib/bind/

```bash
sudo cp /etc/bind/a.internal.hcinfotech.ch.zone /etc/bind/51.1.10.in-addr.arpa.zone /var/lib/bind/
```

- Change permissions to allow bind to update the files

```bash
sudo chown -R bind:bind /var/lib/bind/*
```

- Increase the serial numbers in the SOA records

### 5.2 Change the configuration in /etc/bind/named.conf.local

Update /etc/bind/named.conf.local on the primary name server and add the following section
to any zone prepared for dynamical update:

```conf
update-policy {
  grant ddns-update-key zonesub ANY;
};
```

AppArmor prevents named from updating files in /etc/bind. The zone file needs to be stashed in
directory /var/lib/bind/ in order for it to be updated by named.

Example zone entry in /etc/bind/named.conf.local:

```conf
zone "a.internal.hcinfotech.ch" IN {
  type primary;
  file "/var/lib/bind/a.internal.hcinfotech.ch.zone";
  update-policy {
    grant ddns-update-key zonesub ANY;
  };
};
```

Example: [primary named.conf.local](./config/primary-dns/named.conf.local)

### 5.3 Validate and restart

```bash
sudo -u named-checkconf
sudo -u bind named-checkzone a.internal.hcinfotech.ch a.internal.hcinfotech.ch.zone
```

If everything checks out restart named

```bash
sudo systemctl restart named
```

Check stiatus and logs

```bash
systemctl status named
sudo journalctl -eu named
dig @ns1.a.internal.hcinfotech.ch a.internal.hcinfotech.ch A
```

---

## 6. Dynamic updates with nsupdate

### Add a record

```bash
nsupdate -y $HMAC
```

```code
server ns1.a.internal.hcinfotech.ch
zone a.internal.hcinfotech.ch
update add test.a.internal.hcinfotech.ch. 3600 IN AAAA 2001:db8::1234
send
```

Verify:

```bash
dig @ns1.a.internal.hcinfotech.ch test.a.internal.hcinfotech.ch AAAA
```

### Delete a record

```bash
nsupdate -y $HMAC
```

```code
server ns1.a.internal.hcinfotech.ch
zone a.internal.hcinfotech.ch
update delete test.a.internal.hcinfotech.ch. IN AAAA
send
```

Verify:

```bash
dig @ns1.a.internal.hcinfotech.ch test.a.internal.hcinfotech.ch AAAA
```

I'm temporarily using the following API [bind-rest-api](https://gitlab.com/jaytuck/bind-rest-api.git), based on dnspython. It serves as a start,
but it needs work in parts of the capability and with security.

---

## 8. Security best practices

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

## 9. Next steps

This Dynamic DNS configuration is the foundation for broader reconfiguration:

1. Migrate to IPv6 – replace IPv4 addressing with IPv6
2. Introduce Managed Switches – VLAN support for tenant/service isolation
3. Deploy OPNSense – central routing, firewalling, VLAN separation
4. Adopt Software-Defined Networking (SDN) principles – prepare for multitenant cloud simulation

I document each step in follow-up guides and YouTube walk-throughs.
