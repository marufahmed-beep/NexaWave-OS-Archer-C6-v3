#!/bin/sh
# Run this ON YOUR ROUTER (OpenWrt 25.12, apk) before building, to confirm every package in
# packages.txt really exists in your release's feeds.
#   scp packages.txt check-packages.sh root@192.168.1.1:/tmp/ && ssh root@192.168.1.1 'sh /tmp/check-packages.sh /tmp/packages.txt'
# Exit code 0 = all found, 1 = something missing, 2 = could not read the feeds.

LIST="${1:-./packages.txt}"
[ -r "$LIST" ] || { echo "Cannot read $LIST" >&2; exit 2; }

apk update >/dev/null 2>&1 || { echo "apk update failed (is the router online?)" >&2; exit 2; }

missing=0
for p in $(sed -e 's/#.*//' "$LIST" | xargs); do
	case "$p" in -*) continue ;; esac   # '-pkg' means "remove default package", nothing to look up
	if apk search "$p" 2>/dev/null | grep -Eq "^$p-[0-9]"; then
		echo "ok       $p"
	else
		echo "MISSING  $p"
		missing=1
	fi
done

[ "$missing" -eq 0 ] && echo "All packages found." || echo "Fix or remove the MISSING entries in packages.txt before building."
exit "$missing"
