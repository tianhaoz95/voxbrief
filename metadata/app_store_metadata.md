# Voxbrief · App Store Connect Release Metadata Guide

This document contains all the copy, settings, and URLs required to submit **Voxbrief** to the Apple App Store.

---

## 📱 General Information

| Field | Value | Constraints |
|---|---|---|
| **App Name** | `Voxbrief: Voice Notes to AI` | Max 30 chars (27 chars used) |
| **Subtitle** | `Watch Memos to Structured Docs` | Max 30 chars (30 chars used) |
| **Bundle ID (iOS)** | `com.jacksonzhou666.voxbrief.app` | Matches `project.yml` |
| **Bundle ID (watchOS)** | `com.jacksonzhou666.voxbrief.app.watchkitapp` | Matches `project.yml` |
| **Primary Category** | `Productivity` | |
| **Secondary Category** | `Utilities` | |
| **Primary Language** | `English (U.S.)` | |
| **SKU** | `voxbrief-ios-watch` | |

---

## 🔗 Store URLs

| URL Type | Destination |
|---|---|
| **Support URL** | `https://tianhaoz95.github.io/voxbrief/support.html` |
| **Marketing URL** | `https://tianhaoz95.github.io/voxbrief/` |
| **Privacy Policy URL** | `https://tianhaoz95.github.io/voxbrief/privacy.html` |

---

## ✍️ Listing Copy

### Promotional Text (169 / 170 characters)
```
Capture voice ideas instantly on Apple Watch or iPhone. Transform spoken memos into structured Markdown specs, bullets, and action items with 100% on-device AI.
```

### Keywords (99 / 100 characters)
```
voice memo,speech to text,whisper,transcription,ai notes,apple watch,markdown,on-device,audio recorder
```

### Description
```
Capture ideas at the speed of thought. Voxbrief is the native companion app for Apple Watch and iPhone that transforms spoken stream-of-consciousness thoughts into structured, engineering-grade Markdown notes, technical specifications, and actionable checklists — powered entirely by 100% on-device AI.

Zero cloud servers. Zero account logins. Zero recurring subscriptions. Your voice and your thoughts never leave your personal hardware.

KEY CAPABILITIES & WORKFLOWS

• ONE-TAP APPLE WATCH CAPTURE
Inspiration strikes anywhere — while walking, running, driving, or in transit. Tap a complication widget directly on your watch face (circular, corner, rectangular, or inline) or launch from the Smart Stack Live Activity. Voice memos record instantly in high-efficiency AAC at 32kHz mono, stored securely on watch flash storage with zero battery-draining processing on the wrist. When your iPhone is in range, recordings sync automatically in the background.

• TWO-STAGE ON-DEVICE AI PIPELINE
Once received on iPhone, Voxbrief executes a breakthrough two-stage pipeline:
- Stage 1 (Verbatim Speech-to-Text): On-device OpenAI Whisper (via WhisperKit CoreML) transcribes every spoken word with exceptional punctuation, capitalization, and acoustic accuracy.
- Stage 2 (On-Device LLM Copywriting): Powered by Qwen3 running natively on Apple Silicon via MLX Swift and Metal GPU acceleration. Voxbrief analyzes raw speech, removes filler words ("um", "uh", "like"), structures requirements into bullet points (•), turns sequential logic into numbered conditions (1., 2., 3.), extracts actionable to-dos ([ ]), and tags topics (#architecture, #iOS, #AI).

• TWO PROCESSING TIERS: BUNDLED & OPTIONAL 4B
- Bundled (Qwen3-0.6B-4bit): Built directly into the app (~350 MB). Ready to clean notes immediately upon installation with zero downloads, zero setup, and completely offline capability.
- Downloaded (Qwen3-4B-4bit): An optional 2.3 GB higher-capacity model downloadable on demand from Settings for even deeper nuance, technical synthesis, and executive summaries.
- Private Local LLM Support: Have an Ollama instance running on your Mac or home server? Toggle Local LLM Endpoint in Settings to point to your private server.

• CLEANED NOTE VS. RAW TRANSCRIPT SWITCHER
Never wonder what the AI changed. Toggle seamlessly between:
- Full Rewrite: Structured Markdown with requirements bullets, conditions, checklists, and metadata.
- Light Cleanup: Typos, grammar, and fillers fixed while preserving original phrasing and sentence flow.
- Raw Transcript: Verbatim speech-to-text transcript from Stage 1 Whisper.
- 2-Stage Pipeline Diagnostics: Full transparency into the exact inference engine, models, and latency.

• INTEGRATED AUDIO SCRUBBER
Listen back to original voice recordings with the interactive waveform player, precise timestamp scrubbing, and playback speed controls.

• PRIVACY-FIRST BY DESIGN
Unlike cloud-dependent voice assistants, Voxbrief operates entirely on your device:
- Audio is never uploaded to any remote server or third-party AI provider.
- No analytics, no advertising identifiers, no user tracking.
- All notes are persisted in local sandbox JSON storage that you control.
- Export entire libraries or individual notes to Markdown with one tap.

SYSTEM REQUIREMENTS
- iPhone: iOS 17.0 or later
- Apple Watch: watchOS 10.0 or later
- Supports iPhone 16/17 Pro Max, Dynamic Island, Smart Stack Live Activities, and all Apple Watch sizes (40mm, 42mm, 44mm, 46mm, and Ultra 49mm).
```

### Version What's New (Release Notes)
```
Welcome to Voxbrief 1.1!

What's New in this release:
• Apple Watch 1-Tap Capture: Record voice thoughts effortlessly from watch face complications and Smart Stack Live Activities with zero latency.
• Two-Stage On-Device AI Pipeline:
  - Stage 1: Verbatim speech recognition powered by OpenAI Whisper via WhisperKit CoreML.
  - Stage 2: Structured copywriting, bullets, conditions, and action items powered by Qwen3 via MLX Swift Metal GPU acceleration.
• 100% On-Device Privacy: Your recordings, transcripts, and notes never leave your personal hardware. No cloud servers, no account logins, no telemetry.
• Interactive Audio Player: Inspect waveforms, scrub through timestamps, and verify original audio alongside generated notes.
• Structured Markdown Export: Share clean specs, requirements, and checklists directly into your favorite markdown tools and editors.
• Optional Local LLM Support: Connect directly to a private Ollama endpoint in Settings if desired.
```

---

## 🛡️ App Privacy & Data Safety (App Store Review Guideline 5.1.1)

| Question | Answer |
|---|---|
| **Do you or third-party partners collect data from this app?** | **No, Data Not Collected** |
| **Tracking?** | **No**, Voxbrief does not track users across other apps/websites |
| **Microphone Permission** | Used strictly for user-initiated voice note recordings. Processed 100% locally. |
| **Cloud Telemetry** | **None**. Zero external network requests unless user enters their own Ollama endpoint in Settings. |

---

## 🔒 Export Compliance
- `ITSAppUsesNonExemptEncryption`: `NO` (Declared in `Info.plist`)
- The app uses standard OS-level local file protection and does not use proprietary encryption algorithms requiring BIS classification.

---

## 📋 App Review Information

- **Sign-in Required?**: `No`
- **Review Notes for Apple Reviewer**:
> "Voxbrief requires no login or cloud account. The application performs on-device automatic speech recognition via WhisperKit (CoreML) and on-device NLP structure processing via MLX Swift (Metal GPU). To test on-device memo ingestion on physical hardware or simulator:
> 1. Launch the app; pre-seeded demo voice notes illustrate the formatted markdown and audio scrubber.
> 2. Tap the microphone button in the bottom bar to record a voice note directly on iPhone.
> 3. Go to Settings -> tap 'Simulate Incoming Watch Audio Sync' to inject a sample memo from the Apple Watch companion and watch it process through the 2-Stage pipeline.
> 4. An Apple Watch companion app is included for 1-tap capture via watch complications."
