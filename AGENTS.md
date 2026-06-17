# fluttering_ermine — Agent Guide

## Project Overview

An open-source Flutter client for [Stoat](https://github.com/Stoat-dev/Stoat) (formerly Revolt)-compatible chat platforms. Targets Windows, Linux, macOS, Web, Android, and iOS.

- **State management:** Provider + ChangeNotifier
- **Real-time:** WebSocket via `web_socket_channel`
- **Voice:** LiveKit via `livekit_client`, plus `deepfilter_livekit` for noise suppression and `flutter_webrtc` for WebRTC
- **Platform channels:** `permission_handler`, `file_picker`, `url_launcher`, `shared_preferences`
- **Stoat REST API** consumed through a custom `RevoltService`

Key source directories:
- `lib/models/` — Data classes
- `lib/providers/` — ChangeNotifier state (auth, messaging, server, voice)
- `lib/screens/` — Login and home screens
- `lib/services/` — HTTP, WebSocket, voice event translation
- `lib/widgets/` — UI components

## Local Plugin Dependencies (DO NOT FETCH FROM CACHE)

Two packages are overridden to local/git sources. **Do not waste time trying to fetch them from pub.dev or re-download them.** If they are missing, ask the user:

| Package | Source |
|---|---|
| `deepfilter_livekit` | `dependency_overrides` → local `../deepfilter_livekit` path |
| `flutter_webrtc` | `dependency_overrides` → git (flutter-webrtc main branch) |

If a bug is suspected in either of these plugins:
1. Confirm it is not a usage bug in the app code.
2. Create a separate focused prompt for fixing it in the plugin repo — do not try to patch the plugin inline.
3. Ask the user before making changes to either plugin's source.

## Workflow

- **Break large tasks into smaller prompts.** Use sub-agents for each logical unit of work.
- **Commit only after changes have been verified to work.** Prompt the user at good commit points (e.g. after a feature works, before switching tasks). The user decides when to commit.
- Use `flutter analyze` and `flutter test` to verify before suggesting a commit.

## UI Testing with Flutter Driver

Use `flutter driver` to inspect the widget tree and interact with the application.

- **Durable selectors only.** Identify widgets by text, type, tooltip, or semantics label. Never use temporary IDs or generated keys.
- After every interaction, get the widget tree to see the updated state.
- Avoid reading source files to verify UI state — inspect the live app and widget tree directly.
- If stuck or the driver cannot find a widget, ask the user for help.

## Debugging Procedure

1. **Obtain a stack trace first** — use Flutter's runtime error tools or DTD to capture one. It pinpoints the exact failure site.

2. **No stack trace?** Start at the function where the symptom appears (`function1`). Read its body and analyze what could go wrong.

3. **Widen context outward** — read the callers of `function1`, then their callers, repeating until you either:
   - Find the root cause, or
   - Reach the app boundary (platform channel, service, event stream).

4. **No error found inside the app?** Ask the user for permission before inspecting external dependency sources. Apply the same expanding-context strategy from the call site outward.
