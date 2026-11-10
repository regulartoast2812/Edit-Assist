#!/bin/zsh
# Every check, then every recorded decision replayed. build.sh runs this and installs nothing if it fails.
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/module-cache
SOURCES=(Sources/Models.swift Sources/ScriptParser.swift Sources/AIClient.swift Sources/CLIClient.swift Sources/Desktop.swift
         Sources/LiveFeed.swift Sources/Overlay.swift Sources/PanelReader.swift Sources/PeopleReader.swift Sources/Recorder.swift Sources/Store.swift Sources/Updater.swift Sources/ScriptEditor.swift Sources/Localization.swift Sources/Guide.swift Sources/AmirWatcher.swift Sources/BoWatcher.swift Sources/ElevenLabs.swift Sources/HelperBrain.swift Sources/Studio.swift Sources/KinoDesk.swift Sources/Grafana.swift Sources/GrafanaBoard.swift Sources/PennyLedger.swift Sources/SageStudy.swift Sources/SageResearch.swift Sources/SageNotes.swift Sources/SageDesk.swift Sources/SagePick.swift Sources/SagePlayer.swift Sources/SageDeskPick.swift Sources/SageActions.swift
         Sources/SageVault.swift Sources/SageFiles.swift Sources/SageObsidian.swift Sources/SageBases.swift Sources/SageVaultDesk.swift Sources/SageDeskFiles.swift
         Sources/SageAgent.swift Sources/SageAgentDesk.swift Sources/SageChatMarkdown.swift Sources/SageMedia.swift Sources/SageMediaText.swift Sources/SageComposerText.swift)
# Incremental (Tools/incremental.zsh): only files changed since the last run are recompiled; the checks and the replay
# are compiled side by side.
source Tools/incremental.zsh
CHECKS=(Tests/Checks.swift Tests/SageVaultChecks.swift Tests/SageNotesChecks.swift Tests/SageBasesChecks.swift Tests/SageAgentChecks.swift Tests/SageMediaChecks.swift Tests/SageComposerChecks.swift)
incremental cliworker-test .build/CLIWorker -parse-as-library -module-cache-path .build/module-cache -- Helpers/CLIWorker.swift
incremental checks .build/checks -swift-version 5 -parse-as-library -O -module-cache-path .build/module-cache -- $SOURCES $CHECKS &
checks=$!
incremental replay .build/replay -swift-version 5 -parse-as-library -O -module-cache-path .build/module-cache -- $SOURCES Tests/Replay.swift &
replay=$!
wait $checks
.build/checks
# Real screens and kept recordings: a decision that comes out differently fails the build.
wait $replay
.build/replay Tests/Fixtures
