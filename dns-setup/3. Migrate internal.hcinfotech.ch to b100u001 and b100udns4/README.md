![HCInfoTech Banner](../../common/images/dns-delegation-and-migration-banner.png)

# 🧭 DNS delegation & migration – internal infrastructure

## Purpose:

This module documents the migration of the internal DNS environment to the new delegated architecture under
**b.internal.hcinfotech.ch** — introducing a staged topology that separates authoritative zones from recursive resolvers.

## 📘 Overview

This migration transitions the internal DNS infrastructure to a delegated zone structure:

| Zone                      | Role                       | Primary   | Secondary            |
| ------------------------- | -------------------------- | --------- | -------------------- |
| internal.hcinfotech.ch.   | Root of internal namespace | b100u001  | b100u000             |
| b.internal.hcinfotech.ch. | Primary operational zone   | b100udns4 | b100udns5, b100udns6 |
| 50.1.10.in-addr.arpa.     | Reverse zone               | b100udns4 | b100udns5, b100udns6 |

**Future trust anchor:**

Once DNSSEC is implemented, internal.hcinfotech.ch will become the cryptographic trust anchor for all delegated child zones.

## 🧩 Migration Objectives

- Migrate **A**, **CNAME**, and **PTR** records from the old internal.hcinfotech.ch zone.
- Create separate authoritative zones for b.internal.hcinfotech.ch and its reverse zone.
- Delegate authority from internal.hcinfotech.ch to its subzones.
- Transition existing name servers to **recursive resolvers**.
- Maintain service continuity via **transitional CNAMES**.

---

## ⚙️1. Validate Current Zones

```bash
dig @10.1.50.31 internal.hcinfotech.ch -t AXFR -y $HMAC
dig @10.1.50.84 b.internal.hcinfotech.ch -t AXFR -y $HMAC
```

✅ Expected: Only **SOA** and **NS** records present before migration.

---

## 📦 2. Dump Existing Zone Data

Export **A**, **CNAME**, **MX**, and **PTR** records from the legacy primary.

```bash
dig @ns1.internal.hcinfotech.ch +noall +answer internal.hcinfotech.ch. -y $HMAC -t AXFR \
| grep -E $'[\t| ](A|CNAME|MX)[\t| ]' |sudo tee /etc/bind/internal.hcinfotech.ch.migration

dig @ns1.internal.hcinfotech.ch +noall +answer 50.1.10.in-addr.arpa. -y $HMAC -t AXFR \
| grep -E $'[\t| ](PTR)[\t| ]' |sudo tee /etc/bind/50.1.10.in-addr.arpa.migration
```

NOTE: Variable $HMAC is generated using the alias from [2. Add DDNS to current setup ](../2.%20Add%20DDNS%20to%20current%20setup/README.md)

Copy these migration files to:

- /etc/bind/internal.hcinfotech.ch.migration → **b100u001**, **b100udns4**
- /etc/bind/50.1.10.in-addr.arpa.migration → **b100udns4**

---

## 🧮 3. Prepare Forward Zone Migration

Edit the migration file on b100udns4:

```bash
sudo nvim /etc/bind/internal.hcinfotech.ch.migration
```

**Changes**

- Remove MX and glue records.
- Replace internal. with b.internal.
- Prepend all records with update add.

Add zone and server headers at the top:

```conf
server 10.1.50.84
zone b.internal.hcinfotech.ch.
```

Append:

```conf
send
```

Apply:

```bash
nsupdate -y $HMAC /etc/bind/internal.hcinfotech.ch.migration
```

Validate:

```bash
dig @10.1.50.84 b.internal.hcinfotech.ch -t AXFR -y $HMAC
```

---

## 🔄 4. Reverse Zone Migration

Edit and adapt the PTR migration file:

```bash
sudo nvim /etc/bind/50.1.10.in-addr.arpa.migration
```

- Replace internal → b.internal
- Duplicate each line to include both A and CNAME reverse entries
- Add headers and send block

Apply and verify:

```bash
nsupdate -y $HMAC /etc/bind/50.1.10.in-addr.arpa.migration
dig @10.1.50.84 50.1.10.in-addr.arpa -t AXFR -y $HMAC
```

---

## 🏗️ 5. Configure New Primary Zone (b100u001)

Freeze and edit the top-level internal zone:

```bash
sudo rndc freeze
sudo nvim /var/lib/bind/internal.hcinfotech.zone
```

Add:

```dns
$TTL 86400
internal.hcinfotech.ch. IN SOA ns1.internal.hcinfotech.ch. admin.internal.hcinfotech.ch. (
    2025100305 43200 900 1814400 7200 )
                NS ns1.internal.hcinfotech.ch.
                NS ns2.internal.hcinfotech.ch.
    IN MX 10 b100mail1.internal.hcinfotech.ch.
    IN MX 20 b100mail2.internal.hcinfotech.ch.

a.internal.hcinfotech.ch. IN NS ns1.a.internal.hcinfotech.ch.
                             NS ns2.a.internal.hcinfotech.ch.
                             NS ns2.a.internal.hcinfotech.ch.

ns1.a.internal.hcinfotech.ch. A 10.1.51.81
ns2.a.internal.hcinfotech.ch. A 10.1.51.82
ns3.a.internal.hcinfotech.ch. A 10.1.51.83

b.internal.hcinfotech.ch. IN NS ns1.b.internal.hcinfotech.ch.
                             NS ns2.b.internal.hcinfotech.ch.
                             NS ns2.b.internal.hcinfotech.ch.
ns1.b.internal.hcinfotech.ch. A 10.1.50.84
ns2.b.internal.hcinfotech.ch. A 10.1.50.85
ns3.b.internal.hcinfotech.ch. A 10.1.50.86
```

Then:

```bash
sudo rndc thaw
```

---

## 🧷 6. Create Transitional CNAMES

Convert old A records into CNAMEs pointing to the new delegated zone:

```vim
:%s/^\([A-Za-z0-9\-]*\).*[\ |\t]A[\ |\t].*/\1\.internal\.hcinfotech\.ch\. 600 IN CNAME \1\.b\.internal\.hcinfotech\.ch\./
```

- Prepend every record with 'update add '
- Add server and zone record at the top
- Add send at the bottom

Apply:

```bash
nsupdate -y $HMAC /etc/bind/internal.hcinfotech.ch.migration
```

---

## 🌐 7. Convert Old Servers to Recursive Resolvers

1. Copy ddns-signature from b100u000.
2. Update ownership to bind:bind.
3. Modify named.conf.local to forward 50.1.10.in-addr.arpa to 10.1.50.84.
4. Remove old zone files:

```bash
sudo rm /var/lib/bind/internal.hcinfotech.ch.zone
```

5. Restart and test

```bash
sudo systemctl restart named
dig internal.hcinfotech.ch
```

6. Add also-notify in /etc/bind/named.conf.local on **b100u001**.

---

## ✅ Validation

Use full zone transfer tests and random sample lookups:

```bash
dig +trace +dnssec test.b.internal.hcinfotech.ch
dig -x 10.1.50.84
```

Expected:

- Correct SOA and NS chains
- Proper PTRs for both A and CNAMEs
- CNAMES resolving correctly from old to new namespace

---

## Next Steps

### 🔐 Next Module: DNSSEC

We’ll designate b100u001 as the trust anchor and begin signing both internal.hcinfotech.ch and its delegated subzones.

---
