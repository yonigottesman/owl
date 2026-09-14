#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc Sources/Protocol.swift Tests/SessionTests.swift -o .build/session-tests
.build/session-tests
xcrun swiftc Sources/HelperSetup.swift Tests/HelperSetupTests.swift -o .build/helper-setup-tests
.build/helper-setup-tests
xcrun swiftc Sources/LidDisplay.swift Tests/LidDisplayTests.swift -o .build/lid-display-tests
.build/lid-display-tests
xcrun swiftc Sources/PowerPolicy.swift Tests/PowerPolicyTests.swift -o .build/power-policy-tests
.build/power-policy-tests
xcrun swiftc Sources/EventSources.swift Tests/EventTests.swift -o .build/event-tests
.build/event-tests
xcrun swiftc -import-objc-header Sources/PowerMessages.h Sources/PowerEvents.swift Tests/PowerEventRegistrationTests.swift -o .build/power-events-tests
.build/power-events-tests
/bin/bash -n Resources/install-helper.sh scripts/uninstall.sh build.sh
/usr/bin/plutil -lint Resources/Info.plist
