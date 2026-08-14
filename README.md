# EarTalk

Live translator in your AirPods. Sister app to [NodVoice](https://github.com/GianlucaMinoprio/nodvoice).

You pick the language they speak and the language you want to hear. Grok transcribes, translates, and talks.

1. **Listen** - one mic. Grok STT detects the language.
   - Their language → Eve in your ear (speaker if AirPods are out) + big text in your language.
   - Your language → Eve out loud + big text in their language.

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
5. Set **They speak** / **I speak**
6. Tap **Listen**. Pause after either of you talks. Language picks the side.

## How the loop works

```
They talk  ->  phone mic  ->  Grok STT
           ->  matches They speak
           ->  Grok TTS in your language  ->  AirPods (or speaker)
           ->  big text in your language

You talk   ->  phone mic  ->  Grok STT
           ->  matches I speak
           ->  Grok TTS in their language  ->  speaker
           ->  big text in their language
```

Silence of about 1.5s ends a turn. Their side auto-continues after the ear playback. Your side keeps the caption until Done, then Listen again.

AirPods are optional. Out = no Bluetooth, your side plays on the speaker. Mic is always the phone when they talk.

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
