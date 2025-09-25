![DNSSEC HCInfoTech Banner](../../common/images/dnssec-GitHub-Banner.png)

# DNSSEC setup (Secure zone signing)

This guide walks you through enabling DNSSEC signing for your zone. DNSSEC proves to
DNS resolvers that transferred zone data originates from a trusted authoritative nameserver.
In this way it makes it challenging for attackers to spoof network addresses.

If this would be a zone on the internet the DNSSEC key signing key would be propagated to
the domain registrar and prove of authenticity would flow down all the way from internet root.

Because this configuration is for an intranet site, I select one of my zones as the
top level zone and authenticity flows down from that point.

[Final internal DNS topology](../../common/images/final-internal-dns-topology.png)
---

## 1. Generate DNSSEC keys

Create a controlled directory owned by bind to store the keys

```bash
sudo mkdir -p /usr/local/etc/dnssec-keys

sudo chown bind:bind /usr/local/etc/dnssec-keys
sudo chmod g-w,o-rwx /usr/local/etc/dnssec-keys
```

Use modern algorithms for example ECDSA P-256 for shorter keys and better performance. You create two
key pairs for each zone, ZSK (<u>Z</u>one <u>S</u>igning <u>K</u>ey) and KSK (<u>K</u>ey <u>S</u>igning <u>K</u>ey)

```bash
sudo -u bind dnssec-keygen -K /usr/local/etc/dnssec-keys/ -a ECDSAP256SHA256 -n ZONE internal.hcinfotech.ch
sudo -u bind dnssec-keygen -K /usr/local/etc/dnssec-keys/ -f KSK -a ECDSAP256SHA256 -n ZONE internal.hcinfotech.ch
sudo -u bind dnssec-keygen -K /usr/local/etc/dnssec-keys/ -a ECDSAP256SHA256 -n ZONE 50.1.10.in-addr.arpa
sudo -u bind dnssec-keygen -K /usr/local/etc/dnssec-keys/ -f KSK -a ECDSAP256SHA256 -n ZONE 50.1.10.in-addr.arpa
```

- ECDSAP256SHA256 is a common modern algorithm; adjust as needed.
- The -f KSK flag makes the second key the Key Signing Key (used as root of trust).

---

## 2. Enable DNSSEC in the zones

### 2.1 Define the dnssec-policy

In /etc/bind/named.conf.options:

```conf
...
dnssec-policy "a.internal-policy" {
    keys {
        ksk lifetime 360d algorithm ecdsap256sha256; // KSK lifetime of 1 year
        zsk lifetime 30d algorithm ecdsap256sha256; // ZSK lifetime of 30 days
    };
};
...
```

Assign the policy to dynamic zones in /etc/bind/named.conf.local

```conf
zone "a.internal.hcinfotech.ch" IN {
  type primary;
  ...
  dnssec-policy "a.internal-policy";
  ...
];
```

### 2.2 Sign the zones with the generated keys

```bash
sudo -u bind dnssec-signzone -K /usr/local/etc/dnssec-keys/ -S  \
    -N increment -o internal.hcinfotech.ch -t /var/lib/bind/internal.hcinfotech.ch.zone
sudo -u bind dnssec-signzone -K /usr/local/etc/dnssec-keys/ -S  \
    -N increment -o 50.1.10.in-addr.arpa -t /var/lib/bind/50.1.10.in-adr.arpa.zone
```

- -K: Directory to search for the keys
- -S: Smart signing: dnssec-signzone searches the key repository for corresponding keys for the zones to be signed.
- -N increment: Increments the SOA record serial number

### 2.3 Include the signed zone files in named.conf.local

```conf
zone "internal.hcinfotech.ch" IN {
  type primary;
  file "/var/lib/bind/internal.hcinfotech.ch.zone.signed";
  update-policy {
   grant ddns-update-key zonesub ANY;
  };
};

// zone file for the reverse lookup
zone "50.1.10.in-addr.arpa" {
  type primary;
  file "/var/lib/bind/10.1.50.rev.zone.signed";
  update-policy {
   grant ddns-update-key zonesub ANY;
  };
};
```

### 2.4 Trust anchor / KSK publication

If this are public-facing DNS zones, publish the KSK (key-signing DNSKEY) to the DNS registrar so that resolvers can verify.
This are private-facing DNS zones, configure the primary zone as a trust anchor.

In named.conf.options on the primary name server. The keys are the KSK public keys for the zones (files ending with .key in /usr/local/etc/dnssec-keys/)

```conf
...
trust-anchors {
  "internal.hcinfotech.ch." initial-key 257 3 13 "v/rp5d8ciyhxNK85lWrOi/UbZyua4HKrB54NUkz2mlKX53MaaoO82nNo g2CDShOK5u6tbMft7k9DGw5hoeadTA==";
  "50.1.10.in-addr.arpa." initial-key 257 3 13 "NU4johWLFUTWx3gllXFnx2+60HxACPKaiyyqOzTFMcK4Lne/9WhDiYd0 6PhH2VM1+oM8xGQoJReBVb/ErQ1o6Q==";
};
...
```

Example: [named.conf.options](./config/primary.named.conf.options)

The resolver validate automatic against these keys because of 'dnssec-validation auto;' in named.conf.options.

### 2.5 Validation

After everything is configured perform these tests:

```bash
# Check syntax
sudo named-checkconf
sudo named-checkzone internal.hcinfotech.ch /var/lib/bind/internal.hcinfotech.ch.zone.signed

# Query the zone to check DNSSEC signatures
dig @ns1.internal.hcinfotech.ch internal.hcinfotech.ch SOA +dnssec
dig @ns1.internal.hcinfotech.ch internal.hcinfotech.ch A  +dnssec

# Check if the AD bit is set (Authenticated Data)
dig @ns1.internal.hcinfotech.ch internal.hcinfotech.ch +dnssec +short A

# After setting up HMAC using set_HMAC alias
# Test zone transfer
dig @ns2.internal.hcinfotech.ch internal.hcinfotech.ch AXFR +noall +answer -y ${HMAC}
```

### 2.6 Common Pitfalls & Troubleshooting

| Problem                             | Likely Cause                                                 | Solution                                                            |
| ----------------------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------- |
| DNSSEC validation failure           | Clock skew, wrong signatures, incorrect key usage            | Sync clocks, re-sign, verify that the right DNSKEY is published     |
| Update doesn’t apply to signed zone | Signed zone may get overwritten or updated without resigning | Use automatic signing or manually re-sign after updates             |
| Transfer denied                     | Missing TSIG key in `allow-transfer` or wrong IP             | Check key names and ACLs                                            |
| Named fails to start                | Missing signature files, mismatched file names               | Ensure zone file `.signed` referenced, file permissions are correct |

---

## 3. Automatic re-signing

For dynamic zones consider enabling automatic DNSSEC signing in BIND9 by adding to the zones in named.conf.local:

```conf
zone internal.hcinfotech.ch {
    ...
    inline-signing yes;
    ...
};
```

Example: [named.conf.local](./config/primary.named.conf.local)

---

## 4. Key rollover strategy (ZSK & KSK)

Proper key rollover is critical for maintaining DNSSEC validation without interruption.

### 4.1 ZSK (Zone Signing Key) rollover

ZSKs are used to sign the actual zone data (A, AAAA, MX, etc.). They are typically rolled over more frequently than KSKs.

Recommended Process:

1. Pre-publish new ZSK:
   - Generate a new ZSK and add its DNSKEY record to the zone alongside the old ZSK.
   - Sign the zone with both keys.
   - Publish the updated zone.
2. Wait for TTL to expire:
   - Ensure that the old zone data (with the old ZSK only) has expired from caches.
3. Remove old ZSK:
   - Stop signing with the old ZSK.
   - Remove the old ZSK from the zone.
   - Re-sign and publish.

This ensures validators always have at least one trusted ZSK available during rollover.

### 4.2 KSK (Key Signing Key) rollover

KSKs sign the DNSKEY RRset and are usually more static, changed only occasionally (e.g., yearly).

**Recommended Process:**

1. Pre-publish new KSK:
   - Add the new KSK to the zone, so both the old and new KSK are published.
   - Sign the zone with both keys.
2. Generate and Submit New DS Record:
   - Use dnssec-dsfromkey to generate a DS record for the new KSK.
   - Submit the new DS record to your registrar.
3. Wait for DS Propagation:
   - Verify with dig +dnssec example.com DS that both DS records are visible.
4. Remove Old KSK and DS:
   - After TTL expiry, remove the old KSK and old DS record.
   - Re-sign and publish the zone.

**Timing Considerations**

- Always allow at least two times the maximum TTL between key introduction and removal.
- Automate this process with cron and dnssec-keymgr if possible to avoid human error.

Following these steps minimizes downtime and ensures continuous DNSSEC validation during key rollovers.

### 4.3 Automating ZSK rollover and zone re-signing

Manually re-signing zones and rolling over ZSKs can be error-prone. Automating the process helps maintain security and consistency.

#### 4.3.1 Example: Cron job for zone re-signing

Create a script /usr/local/sbin/dnssec-resign.sh:

```code
#!/bin/bash
ZONE="$1"
ZONEFILE="/var/lib/bind/${2}.zone"
KEYDIR="/usr/local/etc/dnssec-keys/"

# Re-sign the zone using the current keys
cd /var/lib/bind/
dnssec-signzone -K $KEYDIR -S -o $ZONE -N increment $ZONEFILE

# Reload named to apply changes
rndc reload
```

Example: [dnssec-resign.sh](./config/dnssec-resign.sh)

Make the script executable:

```bash
sudo chmod +x /usr/local/sbin/dnssec-resign.sh
```

Add a cron job to re-sign the zone daily:

```bash
sudo -u bind crontab -e
```

Add:

```conf
0 3 * * * /usr/local/sbin/dnssec-resign.sh internal.hcinfotech.ch internal.hcinfotech.ch >/dev/null 2>&1
0 3 * * * /usr/local/sbin/dnssec-resign.sh 50.1.10.in-addr.arpa 10.1.50.rev >/dev/null 2>&1
```

This ensures signatures are refreshed before they expire

---

## 5. Security best practices

1. Key permissions
   - Restrict key files (.key, .private) to be readable only by the bind user and group:

   ```bash
    sudo chown root:bind /usr/local/etc/dnssec-keys/K*
    sudo chmod 640 /usr/local/etc/dnssec-keys/
   ```

   - Ensure /var/lib/bind is not world-readable.

2. Separate KSK and ZSK Responsibilities
   - Keep KSKs offline where possible — only bring them online when re-signing the DNSKEY RRset or rolling over KSKs.
   - ZSKs can remain online for automated signing, as they are rolled over more frequently.
3. Use Hardware Security Modules (HSMs) if available
   - Store private keys in an HSM or a Trusted Platform Module (TPM) to prevent key exfiltration.
   - Configure BIND with PKCS#11 support to sign zones using keys in the HSM.
4. Monitor key expiry
   - Automate monitoring of DNSSEC key and signature expiration using tools like nagios, icinga, or zabbix.
   - Send alerts well before signatures or keys expire to avoid validation failures.
5. Secure rndc and administrative access
   - Protect rndc.key with correct permissions.
   - Limit who can reload, re-sign, or alter zones by restricting sudo privileges.
   - Use SSH with key-based authentication for administrative access to name servers.
6. Document and test disaster recovery
   - Keep a secure backup of keys offline.
   - Regularly test restoring keys and re-signing zones in a staging environment to ensure you can recover from data loss.

Following these practices will strengthen your DNSSEC deployment and reduce the risk of compromise or downtime.
