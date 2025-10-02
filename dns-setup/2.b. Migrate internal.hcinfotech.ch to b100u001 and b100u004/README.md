# Migrate internal.hinfooooooootech.ch

## 1. Configure b.internal.hcinfotech.ch.

### Configure dynamic DNS on b100udns4, b100udns5 and b100udns5

Follow steps in [2. Add DDNS to current setup](../2.%20Add%20DDNS%20to%20current%20setup/README.md)

### Setup zones b.internal.hcinfotech.ch and 50.1.10.in-addr.arpa

On b100udns4:

- Freeze named

```bash
sudo rndc freeze
```

- Copy internal.hcinfotech.ch and 50.1.in-addr.arpa from b100u002

```bash
sudo scp b100u002:/var/lib/bind/internal.hcinfotech.ch.zone /var/lib/bind/b.internal.hcinfotech.ch.zone
sudo scp b100u002:/var/lib/bind/50.1.10.in-addr.arpa.zone /var/lib/bind/
```

- Change all occurrences of internal.hcinfotech.ch in /var/lib/bind/b.internal.hcinfotech.ch.zone to b.internal.hcinfotech.ch

- Change the NS records to the correct nameservers

- Bump the serial

- Repeate for 50.1.10.in-addr.arpa.zone

- Reload and thaw

```bash
sudo rndc reload
sudo rndc thaw
```

## 2. Configure b100u001 and b100u000

## 3. Convert b100u002 to recursive resolver
