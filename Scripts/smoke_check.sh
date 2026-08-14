#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

missing=0
need=(
  EarTalk/App/EarTalkApp.swift
  EarTalk/App/SessionController.swift
  EarTalk/Models/Models.swift
  EarTalk/Services/AudioCaptureService.swift
  EarTalk/Services/SpeechPlayer.swift
  EarTalk/Services/SuperGrokAuth.swift
  EarTalk/Services/XAIClient.swift
  EarTalk/Utilities/KeychainStore.swift
  EarTalk/Utilities/SpokenLanguage.swift
  EarTalk/Utilities/DemoLines.swift
  EarTalk/Utilities/SpeakerSense.swift
  EarTalk/Utilities/TranscriptMerge.swift
  EarTalk/Views/RootView.swift
  EarTalk/Views/SettingsView.swift
  EarTalk/Views/SuperGrokSignInView.swift
  EarTalk/Views/CaptionBoardView.swift
  EarTalk/Info.plist
  EarTalk.xcodeproj/project.pbxproj
  EarTalk.xcodeproj/xcshareddata/xcschemes/EarTalk.xcscheme
)
for f in "${need[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "MISSING $f"
    missing=1
  fi
done

if ! grep -q "EarTalkApp.swift in Sources" EarTalk.xcodeproj/project.pbxproj; then
  echo "pbxproj missing EarTalkApp.swift"
  missing=1
fi
if ! grep -q "CaptionBoardView.swift in Sources" EarTalk.xcodeproj/project.pbxproj; then
  echo "pbxproj missing CaptionBoardView.swift"
  missing=1
fi
if head -1 EarTalk.xcodeproj/xcshareddata/xcschemes/EarTalk.xcscheme | grep -qv '<?xml'; then
  echo "scheme is not pure XML"
  missing=1
fi

if [[ "$missing" -ne 0 ]]; then
  exit 1
fi
echo "smoke_check ok"
