#!/bin/sh
#
# randomize MAC address before connecting to wifi or ethernet
#
# This script should always be run in if-pre-up.d, but unfortunately
# NetworkManager does not run if-pre-up.d scripts before it sets up a network
# connection (https://bugzilla.gnome.org/show_bug.cgi?id=387832).
# if-post-down.d scripts are run, so there is a symlink to this script
# there. That means when running network config from the terminal, macchanger
# will be run twice, but it'll only be run in if-post-down.d when using
# NetworkManager.

package=macchanger

. /etc/default/${package}

LOGFILE=/var/log/${package}.log

if [ "$ENABLE_ON_POST_UP_DOWN" != "true" ]; then
    echo "disabled in /etc/default/${package}" >> $LOGFILE
    exit
fi

echo "IFACE = $IFACE" >> $LOGFILE

# quit if we're called for the loopback
if [ "$IFACE" = lo ]; then
    echo "ignoring loopback" >> $LOGFILE
    exit 0
fi

# if ENABLE_INTERFACES is set, quit if IFACE not in that list
if [ -n "$ENABLE_INTERFACES" ]; then
    case "$ENABLE_INTERFACES" in
        *"$IFACE"*)
            # IFACE* is found, continue
        ;;
        *)
            echo "ignoring $IFACE" >> "$LOGFILE";
            exit 0 # IFACE not found, exit
        ;;
    esac
fi

/usr/bin/${package} -e $IFACE >> $LOGFILE 2>&1
