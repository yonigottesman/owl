#!/bin/bash
set -euo pipefail
if [[ "$EUID" -ne 0 ]]; then
    echo "Run: sudo /bin/bash scripts/uninstall.sh"
    exit 1
fi
/bin/launchctl bootout system /Library/LaunchDaemons/com.yonigo.Owl.helper.plist 2>/dev/null || true
if [[ -f /var/db/com.yonigo.Owl.active ]]; then
    /usr/bin/pmset -a disablesleep 0
    /bin/rm /var/db/com.yonigo.Owl.active
fi
/bin/rm -f /Library/LaunchDaemons/com.yonigo.Owl.helper.plist /Library/PrivilegedHelperTools/com.yonigo.Owl.helper
/bin/rm -rf /var/run/com.yonigo.Owl
echo "Owl helper removed; normal sleep restored. You can delete Owl.app."
