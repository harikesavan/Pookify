# leanring-buddy — Main App Target

> 22 Swift files, ~7,751 LOC. Organized into subdirectories by domain.

## Directory Structure

```
leanring-buddy/
├── App/           Entry point, central orchestrator, runtime config
├── Voice/         Push-to-talk, mic capture, transcription providers
├── AI/            API clients (OpenAI, Claude, ElevenLabs, element detection)
├── UI/            Menu bar panel, overlay, design system
├── Utilities/     Screenshots, permissions, analytics
├── Resources/     Assets, audio files, images
├── Info.plist
├── leanring-buddy.entitlements
└── AGENTS.md
```

## WHERE TO LOOK

| Task | File(s) | Dir | Notes |
|------|---------|-----|-------|
| App bootstrap / lifecycle | `leanring_buddyApp.swift` | App/ | `@main` + `CompanionAppDelegate` inline. No separate AppDelegate file. |
| Voice state machine | `CompanionManager.swift` | App/ | Central orchestrator. Owns dictation, OpenAI API, TTS, overlay, onboarding. 9 MARK sections. |
| Runtime config | `AppBundleConfiguration.swift` | App/ | Reads keys from `Info.plist` at runtime. |
| Menu bar icon + panel | `MenuBarPanelManager.swift` | UI/ | `NSStatusItem` + custom borderless `NSPanel`. Non-activating, auto-dismiss on outside click. |
| Panel UI (dropdown) | `CompanionPanelView.swift` | UI/ | SwiftUI. Model picker, permissions, push-to-talk instructions, quit button. |
| Cursor overlay | `OverlayWindow.swift` | UI/ | Full-screen transparent `NSPanel` via `NSHostingView`. Cursor animation, bezier arc pointing, multi-monitor coordinate mapping. |
| Response bubble + waveform | `CompanionResponseOverlay.swift` | UI/ | SwiftUI view rendered in the overlay next to the cursor. |
| Design tokens | `DesignSystem.swift` | UI/ | `DS.Colors.*`, `DS.CornerRadius.*`, button styles. All UI references this. |
| Push-to-talk pipeline | `BuddyDictationManager.swift` | Voice/ | `AVAudioEngine` mic capture, provider-aware permissions, transcript finalization, contextual keyterms. |
| Global hotkey | `GlobalPushToTalkShortcutMonitor.swift` | Voice/ | Listen-only `CGEvent` tap (not AppKit global monitor). Publishes press/release transitions. |
| Transcription protocol | `BuddyTranscriptionProvider.swift` | Voice/ | Protocol + factory. Provider resolved from `Info.plist` `VoiceTranscriptionProvider` key. |
| Transcription (default) | `AssemblyAIStreamingTranscriptionProvider.swift` | Voice/ | Real-time websocket (`u3-rt-pro`). Fetches temp token from Worker. **Shares a single `URLSession`** — never create per-session. |
| Transcription (upload) | `OpenAIAudioTranscriptionProvider.swift` | Voice/ | Buffers audio, uploads WAV on key-up. |
| Transcription (local) | `AppleSpeechTranscriptionProvider.swift` | Voice/ | Apple Speech framework fallback. |
| Audio conversion | `BuddyAudioConversionSupport.swift` | Voice/ | PCM16 mono conversion, WAV payload builder. |
| OpenAI chat | `OpenAIAPI.swift` | AI/ | GPT-4o vision client with SSE streaming. Routes through Worker proxy. |
| Claude chat | `ClaudeAPI.swift` | AI/ | SSE streaming + non-streaming. Currently unused (kept as reference). |
| TTS playback | `ElevenLabsTTSClient.swift` | AI/ | Worker proxy → `AVAudioPlayer`. Exposes `isPlaying` for transient cursor scheduling. |
| Element pointing | `ElementLocationDetector.swift` | AI/ | Uses Claude Computer Use API to detect UI element coordinates in screenshots. |
| Screenshots | `CompanionScreenCaptureUtility.swift` | Utilities/ | ScreenCaptureKit multi-monitor capture. Returns labeled image data per display. |
| Window placement + perms | `WindowPositionManager.swift` | Utilities/ | Screen Recording permission gate, accessibility permission helpers, window positioning. |
| Analytics | `ClickyAnalytics.swift` | Utilities/ | PostHog integration. |

## CODE MAP — Key Symbols

| Symbol | Type | File | Role |
|--------|------|------|------|
| `CompanionVoiceState` | enum | CompanionManager | `.idle` / `.listening` / `.processing` / `.responding` |
| `CompanionManager` | class | CompanionManager | Central `@MainActor ObservableObject`. Owns everything. |
| `CompanionManager.start()` | method | CompanionManager | Bootstrap: permissions → polling → bindings → TLS warmup → overlay |
| `CompanionManager.sendTranscriptToAIWithScreenshot` | method | CompanionManager | Core pipeline: screenshot → OpenAI SSE → parse pointing → TTS |
| `CompanionManager.handleShortcutTransition` | method | CompanionManager | Push-to-talk state machine (pressed → record, released → finalize) |
| `BuddyDictationManager` | class | BuddyDictationManager | Mic capture + transcript lifecycle |
| `BuddyTranscriptionProvider` | protocol | BuddyTranscriptionProvider | Abstraction over AssemblyAI/OpenAI/Apple Speech |
| `BuddyPushToTalkShortcut` | enum | BuddyDictationManager | Shortcut options + transition detection logic |
| `MenuBarPanelManager` | class | MenuBarPanelManager | `NSStatusItem` + `NSPanel` lifecycle |
| `OverlayWindowManager` | class | OverlayWindow | Creates/manages full-screen overlay panels per screen |
| `PointingParseResult` | struct | CompanionManager | Parsed `[POINT:x,y:label:screenN]` tag data |
| `DS` | enum | DesignSystem | Namespace for all design tokens |

## CONVENTIONS (specific to this directory)

- **Organized by domain**: Files grouped into `App/`, `Voice/`, `AI/`, `UI/`, `Utilities/`, `Resources/`. Xcode auto-syncs via `PBXFileSystemSynchronizedRootGroup`.
- **MARK sections**: Large files use `// MARK: - Section Name` to organize logical subsystems (CompanionManager has 9 sections).
- **Provider pattern**: Transcription uses protocol + factory + Info.plist key. Add new providers by implementing `BuddyTranscriptionProvider` and registering in `BuddyTranscriptionProviderFactory`.
- **AppKit bridging**: `NSPanel` + `NSHostingView` for menu bar panel and overlay. Comments explain "why" for all bridging code.
- **No `@EnvironmentObject`**: State flows through `CompanionManager` passed explicitly to views via init parameters.

## ANTI-PATTERNS (this directory only)

- **Never create/destroy `URLSession` per AssemblyAI session** — use `sharedWebSocketURLSession`. Per-session sessions corrupt the OS connection pool.
- **Never suppress type errors** with force casts or `// swiftlint:disable` — fix them properly.
- **Never suppress or ignore the deprecated onChange warning** in OverlayWindow.swift — it's a known non-blocking warning, leave it.
- **Never add features/refactor beyond what was asked** — scope discipline.
- **Never add docstrings/comments to code you didn't change.**

## TESTS

- Unit tests: `leanring-buddyTests/` — Swift Testing framework, 3 tests for `WindowPositionManager` permission logic only
- UI tests: `leanring-buddyUITests/` — XCTest, placeholder/boilerplate
- Coverage: ~0.5%. Most code untested.
