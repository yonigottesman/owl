#!/bin/bash
set -euo pipefail
HELPER="$1"
OWNER_UID="$2"
LABEL=com.yonigo.Owl.helper
DEST=/Library/PrivilegedHelperTools/$LABEL
PLIST=/Library/LaunchDaemons/$LABEL.plist
[[ "$OWNER_UID" =~ ^[0-9]+$ ]] && [[ "$OWNER_UID" -gt 0 ]]
/bin/mkdir -p /Library/PrivilegedHelperTools
/bin/launchctl bootout system "$PLIST" 2>/dev/null || true
/bin/rm -f /var/run/com.yonigo.Owl/status.json
/usr/bin/install -o root -g wheel -m 755 "$HELPER" "$DEST"
/bin/cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$DEST</string><string>$OWNER_UID</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>3</integer>
</dict></plist>
EOF
/usr/sbin/chown root:wheel "$PLIST"
/bin/chmod 644 "$PLIST"
/bin/launchctl bootstrap system "$PLIST"
