# EarTalk

Live translator in your AirPods. Sister app to [NodVoice](https://github.com/GianlucaMinoprio/nodvoice).

You pick the language they speak and the language you want to hear. Grok transcribes, translates, and talks.

1. **Hear them** - phone mic catches their Chinese (or whatever you picked). Translation plays **in your AirPods** with Eve.
2. **I speak** - you talk in your language. Grok speaks their language **out the iPhone speaker** and puts the translation in **huge text** so they can read along.

No API key. Sign in with SuperGrok.

## Requirements

- Mac with Xcode 16+
- iPhone on iOS 17+
- AirPods (or any Bluetooth buds) for the in-ear half
- [xAI](https://console.x.ai/) SuperGrok / X Premium+. Sign in in Settings.

Simulator runs the full UI and demo loop. Real STT / TTS needs SuperGrok on a device.

## Quick start

```bash
git clone https://github.com/GianlucaMinoprio/eartalk.git
cd eartalk
open EarTalk.xcodeproj
```

1. Select your Team under Signing and Capabilities
2. Build to your iPhone
3. Open the app, Settings, Sign in with SuperGrok
4. Put AirPods in, grant mic permission
5. Set **They speak** / **I hear**
6. Point the phone at them, tap **Hear them**. Pause. Translation lands in your ear.
7. Tap **I speak**, talk, pause. They hear it and see the big text.

## How the loop works

```
They talk  ->  phone mic  ->  Grok STT (their language)
           ->  Grok chat translate
           ->  Grok TTS in your language  ->  AirPods

You talk   ->  mic  ->  Grok STT (your language)
           ->  Grok chat translate
           ->  Grok TTS in their language  ->  speaker
           ->  full-screen caption for them to read
```

Silence of about 1.5s ends a turn. Hear them keeps listening after each ear playback. I speak shows the caption until you tap Done.

Point the phone at them when they talk. AirPods mic would hear you, not them, so Hear them forces the built-in mic.

## Architecture

```
EarTalk/
  App/                 SwiftUI entry + session
  Models/              Phase, conversation turn
  Services/
    AudioCaptureService.swift   AVAudioRecorder (m4a) + route
    SuperGrokAuth.swift         Device-code SuperGrok OAuth + Keychain
    XAIClient.swift             STT + translate + TTS
    SpeechPlayer.swift          AirPods vs speaker
  Views/               Languages, live turn, caption board, Settings
```

### xAI endpoints

| Step | Endpoint | Notes |
|------|----------|--------|
| STT | `POST https://api.x.ai/v1/stt` | multipart `file` + language |
| Translate | `POST https://api.x.ai/v1/chat/completions` | JSON `{"translation":"..."}` |
| TTS | `POST https://api.x.ai/v1/tts` | JSON `{ text, voice_id, language }` to raw mp3 |

Default chat model is `grok-4.5` with `reasoning_effort: low`. Swap to `grok-4-1-fast-non-reasoning` or `grok-4.6` in Settings. Default voice is Eve.

Without SuperGrok sign-in the app runs a **demo loop** so the UI still works.

### SuperGrok OAuth

Settings, Sign in with SuperGrok starts xAI device-code OAuth (same family as NodVoice / Hermes). Safari opens, you approve, EarTalk stores access + refresh tokens in Keychain.

Some SuperGrok tiers still get HTTP 403 on audio. That is a product gap, not a reason to paste a console key.

### Simulator hooks

```bash
xcrun simctl launch <udid> com.gianlucaminoprio.eartalk speak
xcrun simctl launch <udid> com.gianlucaminoprio.eartalk hear
xcrun simctl openurl <udid> 'eartalk://hear'
xcrun simctl openurl <udid> 'eartalk://speak'
xcrun simctl openurl <udid> 'eartalk://stop'
xcrun simctl openurl <udid> 'eartalk://reset'
xcrun simctl openurl <udid> 'eartalk://caption'
```

Prefer launch argv. `openurl` can show "Open in EarTalk?" if another app is in front.

## Security

This is a personal demo client. Official xAI mobile guidance for shipping apps is still [ephemeral tokens](https://docs.x.ai/developers/model-capabilities/audio/ephemeral-tokens) in front of a backend key.

## License

MIT.
