![HCInfoTech Banner](../../common/images/HC_InfoTech_Tutorials_Banner.png)

# Reconfiguration of the current DNS infrastructure

## Dynamic DNS setup

### Create the TSIG keys

- Zone Transfer Key

```bash
tsig-keygen -a hmac-sha512 ddns-transfer-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1
```

- Zone Update Key

```bash
tsig-keygen -a hmac-sha512 ddns-update-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1
```

- Change ownership and permissions of the key file to protect it from unauthorized access

```bash
sudo chown root:bind /etc/bind/ddns-signatures
sudo chmod g-w,o-rwx /etc/bind/ddns-signatures
```

- Add the generated keys to a Vault or a similar key management facility. All users allowd to execute zone transfers need
  key ddns-transfer-key. Users allowd to update the zone need the ddns-update-key for this purpose.

### Configure named to use TSIG signed transfers and updates

- Add file /etc/bind/ddns-signatures to /etc/bind/named.conf

```bash
...
include "/etc/bind/ddns-sgnatures";
...
```

- Configure the zones to require the transfer key for zone transfers. For each zone desired add the following to the
  allow-transfer sections:

```bash
allow-transfer {
  ...
  ip addresses allowd for transfer
  ...
  key ddns-transfer-key;
};
```

Pay attention to the semicolons, omitting those is a common error.

- Restart named

```bash
sudo systemctl restart named
```

With this configuration zone transfers require now authentication using the transfer key. I
added the key to my Keepass database. And I am creating some bash aliases for myself, to
facilitate the key setup. With this alias the key will not be displayed on the terminal
ans will not be shown in the bash history.

In .bash_aliases

```bash
alias set_HMAC='read -i "hmac-sha512 " -ep "Encrypt. Algorithm " HMAC_ALG;read -i "ddns-update-key " -ep "DDNS User " HMAC_USER;read -sep "DDNS Password " HMAC_PASSWD;HMAC=${HMAC_ALG}:${HMAC_USER}:${HMAC_PASSWD}'
```

This will create environment variable HMAC, which then can be used in dig and later in nsupdate

For a zone transfer using dig, as an example:

```bash
dig @ns1.in.hcinfotech.ch +noall +answer in.hcinfotech.ch -y $HMAC -t AXFR|grep -E $'[\t| ](A|CNAME|MX)[\t| ]'
```

This is contacting the primary name server for zone in.hcinfotech.ch, initiates a zone transfer AXFR and filters out
the MX, A and CNAME recors.
