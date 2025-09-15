![DNSSEC HCInfoTech Banner](../../common/images/dnssec-GitHub-Banner.png)

# DNSSEC setup (Secure zone signing)

This guide walks you through enabling DNSSEC signing for your zone. DNSSEC proves to
DNS resolvers that transferred zone data originates from a trusted authoritative nameserver.
In this way it makes challenging for attackers to spoof network addresses.

If this would be a zone on the internet the DNSSEC key signing key would be propagated to
the domain registrar and prove of authenticity would flow down all the way from top level
zone, forme .ch.

Because this configuration is for an intranet site, I select one of my zones as the
top level zone and authenticity flows down from that point.

## 1. Generate DNSSEC keys

Use modern algorithms like ECDSA P-256 for shorter keys and better performance.

```bash
cd /var/lib/bind
dnssec-keygen -a ECDSAP256SHA256 -n ZONE tst.hcinfotech.ch
dnssec-keygen -a ECDSAP256SHA256 -n ZONE -f KSK tst.hcinfotech.ch
```
