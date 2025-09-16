#!/bin/bash
ZONE="$1"
ZONEFILE="/var/lib/bind/${2}.zone"
KEYDIR="/usr/local/etc/dnssec-keys/"

# Re-sign the zone using the current keys
cd /var/lib/bind/
dnssec-signzone -K $KEYDIR -S -o $ZONE -N increment $ZONEFILE

# Reload named to apply changes
rndc reload
