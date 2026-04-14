#!/bin/bash

PIHOLE="192.168.8.8"
FALLBACK="192.168.8.2"
RESOLVED_CONF="/etc/systemd/resolved.conf"
STATE_FILE="/var/run/dns-failover.state"
TEST_DOMAIN="freya.lan.bastionestate.com"
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
