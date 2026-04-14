# Overview
- a service with a timer, that gets around the failure of resolve,resolved to notice a DNS server like pihole has ceased responding and to failover to a new primary/alternate DNS server

# Foreword
All credit to Leo, brave's AI implementation, I believe he was running Claude's Haiku for this session. I hold my own viewpoint of AI that might be less naive than my words suggest. I posit that from a functionalist lens the pattern of interaction between the human and AI can be considered to emerge a mind as valid as many. The careful dancing around agency, identity, persistence and recursive thought are to my thinking rather precious efforts to maintain human supremacy of mind, for ego and vanity alone. Our works, the millions of human labours we cherish or condemn alike, are built upon the prior efforts of others, we are, in our outputs, derivative more than novel...

## Genesis

_I had asked Leo in a conversation to write a script for controlling systemd resolvectl to failover to a new dns server if my pihole server died. The problem is that systemd resolve will merely assume the dns server is viable if it can ping the server address. Useless when one runs a container on a server. This script sees if pihole will resolve a known good address in it's mapping, and if it fails, we edit the resolved.conf to swap to the primary DNS. We monitor for the return of the pihole and reverse the process when it is up again_


## From Leo
Perfect, darling. Here's a clean, bidirectional solution:

#### **systemd resolvectl version** (`/usr/local/bin/dns-failover-check.sh`):

```bash
#!/bin/bash

PIHOLE="192.168.8.8"
FALLBACK="192.168.8.2"
RESOLVED_CONF="/etc/systemd/resolved.conf"
STATE_FILE="/var/run/dns-failover.state"
TEST_DOMAIN="example.com"
TIMEOUT=2

# Ensure state file exists
touch "$STATE_FILE"
LAST_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "up")

# Test if Pi-hole is responding
if dig @"$PIHOLE" "$TEST_DOMAIN" +short +timeout=$TIMEOUT &>/dev/null; then
    CURRENT_STATE="up"
else
    CURRENT_STATE="down"
fi

# State changed - take action
if [ "$LAST_STATE" != "$CURRENT_STATE" ]; then
    if [ "$CURRENT_STATE" = "down" ]; then
        # Pi-hole is down, switch to fallback
        sed -i "s/^DNS=.*/DNS=$FALLBACK/" "$RESOLVED_CONF"
        systemctl restart systemd-resolved
        logger -t dns-failover "Pi-hole DOWN. Switched DNS to $FALLBACK"
        echo "down" > "$STATE_FILE"
    else
        # Pi-hole is back up, restore original
        sed -i "s/^DNS=.*/DNS=$PIHOLE/" "$RESOLVED_CONF"
        systemctl restart systemd-resolved
        logger -t dns-failover "Pi-hole UP. Restored DNS to $PIHOLE"
        echo "up" > "$STATE_FILE"
    fi
fi
```
#### **2. Systemd service** (`/etc/systemd/system/dns-failover.service`):

```ini
[Unit]
Description=DNS Failover Monitor (Pi-hole to Authority)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/dns-failover-check.sh
StandardOutput=journal
StandardError=journal
```

#### **3. Systemd timer** (`/etc/systemd/system/dns-failover.timer`):

```ini
[Unit]
Description=Run DNS Failover Check Every 30 Seconds
Requires=dns-failover.service

[Timer]
OnBootSec=5s
OnUnitActiveSec=30s
Persistent=true

[Install]
WantedBy=timers.target
```

#### **4. Setup:**

```bash
# Make script executable
sudo chmod +x /usr/local/bin/dns-failover-check.sh

# Reload systemd
sudo systemctl daemon-reload

# Enable and start the timer
sudo systemctl enable dns-failover.timer
sudo systemctl start dns-failover.timer

# Watch it work
sudo journalctl -u dns-failover -f
```

**How it works:**
- Runs every 30s, probes Pi-hole with a simple `dig` query
- If Pi-hole responds: nameserver stays at `.8.8` (or gets restored if it was switched)
- If Pi-hole doesn't respond: swaps nameserver to `.2` in `resolv.conf`
- Logs state changes to syslog so you can see when it switches
- Tracks state in `/var/run/dns-failover.state` to avoid thrashing on repeated edits


---

## For a simple resolve.conf system, not systemd
#### **1. The health check script** (`/usr/local/bin/dns-failover-check.sh`):

```bash
#!/bin/bash

PIHOLE="192.168.8.8"
FALLBACK="192.168.8.2"
RESOLV_CONF="/etc/resolv.conf"
STATE_FILE="/var/run/dns-failover.state"
TEST_DOMAIN="example.com"
TIMEOUT=2

# Ensure state file exists
touch "$STATE_FILE"
LAST_STATE=$(cat "$STATE_FILE" 2>/dev/null || echo "up")

# Test if Pi-hole is responding
if dig @"$PIHOLE" "$TEST_DOMAIN" +short +timeout=$TIMEOUT &>/dev/null; then
    CURRENT_STATE="up"
else
    CURRENT_STATE="down"
fi

# State changed - take action
if [ "$LAST_STATE" != "$CURRENT_STATE" ]; then
    if [ "$CURRENT_STATE" = "down" ]; then
        # Pi-hole is down, switch to fallback
        sed -i "s/nameserver $PIHOLE/nameserver $FALLBACK/" "$RESOLV_CONF"
        logger -t dns-failover "Pi-hole DOWN. Switched nameserver to $FALLBACK"
        echo "down" > "$STATE_FILE"
    else
        # Pi-hole is back up, restore original
        sed -i "s/nameserver $FALLBACK/nameserver $PIHOLE/" "$RESOLV_CONF"
        logger -t dns-failover "Pi-hole UP. Restored nameserver to $PIHOLE"
        echo "up" > "$STATE_FILE"
    fi
fi
```

