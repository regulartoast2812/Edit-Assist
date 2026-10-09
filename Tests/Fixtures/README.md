# Fixtures

Real screens with decisions checked by eye. `Tests/Replay.swift` replays them on every build.
Each JSON holds the OCR reading of its PNG, so the replay does not depend on OCR being identical
from run to run.

Regenerate or add cases by editing the list in `Tests/MakeFixtures.swift` (kept on this Mac only: it names client screenshots), then (with the source
screenshots in a folder):

    sed 's/^@main$//' Tests/Replay.swift > .build/ReplayLib.swift
    xcrun swiftc -swift-version 5 -parse-as-library -O Sources/{Models,ScriptParser,AIClient,CLIClient,Desktop,LiveFeed,Overlay,Recorder,Store}.swift .build/ReplayLib.swift Tests/MakeFixtures.swift -o .build/makefixtures
    .build/makefixtures <folder with the screenshots>

The generator refuses to write a case the current code does not decide as expected.
