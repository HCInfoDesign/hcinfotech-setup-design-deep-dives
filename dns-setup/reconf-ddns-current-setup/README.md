![HCInfoTech Banner](../../common/images/HC_InfoTech_Tutorials_Banner.png)

# Reconfiguration of the current DNS infrastructure

## Dynamic DNS setup

### Create the TSIG keys

- Zone Transfer Key

```bash
tsig-keygen -a hmac-sha512 ddns-trasfer-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1
```

- Zone Update Key

```bash
tsig-keygen -a hmac-sha512 ddns-update-key | sudo tee -a /etc/bind/ddns-signatures 1>/dev/null 2>&1
```

- Change ownership and permissions of the key file to protect it from unauthorized access

```bash
sudo chown root:bind /etc/bind/ddns-signatures
sudo chmod g-wo-rwx /etc/bind/ddns-signatures
```
