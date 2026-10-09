#!/bin/zsh
# Every check, then every recorded decision replayed. build.sh runs this and installs nothing if it fails.
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/module-cache
SOURCES=(Sources/Models.swift Sources/ScriptParser.swift Sources/AIClient.swift Sources/CLIClient.swift Sources/Desktop.swift
         Sources/LiveFeed.swift Sources/Overlay.swift Sources/Recorder.swift Sources/Store.swift)
xcrun swiftc -parse-as-library -module-cache-path .build/module-cache Helpers/CLIWorker.swift -o .build/CLIWorker
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache $SOURCES Tests/Checks.swift -o .build/checks
.build/checks
# Real screens and kept recordings: a decision that comes out differently fails the build.
xcrun swiftc -swift-version 5 -parse-as-library -O -module-cache-path .build/module-cache $SOURCES Tests/Replay.swift -o .build/replay
.build/replay Tests/Fixtures
