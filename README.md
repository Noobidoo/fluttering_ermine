# fluttering_ermine

An open-source Flutter client for Revolt-compatible chat platforms. Targets Windows, Linux, macOS, Web, Android, and iOS.

Supports core messaging with text, reply chains, inline editing, deletion, emoji reactions, and file attachments. Real-time updates come through a WebSocket connection. Voice channels use LiveKit for audio and screen sharing.

## Features

- Send, edit, delete, and reply to messages
- Emoji reactions with a picker
- File and image attachment uploads
- Voice channels with mute, screen sharing, and participant management
- Real-time typing indicators
- Responsive layout: wide mode with a three-panel view, narrow mode with a drawer
- Dark theme with custom accent colors
- Custom server URL support for self-hosted instances

## Getting Started

**Prerequisites:** Flutter SDK 3.11 or later (stable channel).

```bash
# Fetch dependencies
flutter pub get

# Run the app (auto-selects a device)
flutter run

# Run on a specific platform
flutter run -d chrome       # Web
flutter run -d windows      # Windows
flutter run -d linux        # Linux
flutter run -d macos        # macOS
flutter run -d android      # Android

# Run tests
flutter test

# Run the analyzer
flutter analyze

# Build for release
flutter build web --release
flutter build windows --release
flutter build linux --release
```

## Architecture

The app uses the Provider pattern with ChangeNotifier for state management.

Key layers:

- **RevoltService** handles all HTTP REST calls and the WebSocket connection. It exposes a stream of raw events from the server.
- **VoiceEventService** translates raw WebSocket voice events into typed domain event objects.
- **AuthState** manages login, session tokens, and the current user. It also orchestrates the initial connection sequence.
- **ServerState** tracks the list of servers and channels, plus what is currently selected.
- **MessagingState** manages messages, the user cache, reply composition, typing indicators, and reactions.
- **VoiceState** manages the LiveKit room connection, mute state, screen sharing, and remote participants.

The entry point in `lib/main.dart` wires these together with MultiProvider and switches between the login screen and home screen based on authentication state.

## Project Layout

```
lib/
  main.dart                  App entry point and provider tree
  models/                    Data classes for messages, users, servers, channels, files, voice events
  providers/                 ChangeNotifier state classes (auth, messaging, server, voice)
  screens/                   Login and home screens
  services/                  HTTP client, WebSocket, voice event translation, volume helpers
  widgets/                   UI components: server rail, channel list, chat panel, message bubbles
test/
  helpers/                   Test utilities: mock providers, fake services, widget wrappers
  models/                    Model unit tests
  providers/                 Provider behavior tests
  widgets/                   Widget tests for message rendering and interaction
android/ ios/ linux/ macos/ web/ windows/
                             Platform-specific project files
assets/
  fluttering_ermine.svg      App icon source
```

## Roadmap

Core messaging is mostly complete. Remaining work is tracked in two documents:

- **Todo.md** covers the next phases: unread tracking, member lists, profiles, server management, voice polish, and general polish.
- **ROADMAP.md** covers post-MVP features aiming for Discord parity: rich messages, social graph, notification system, theme system, and more.

## Credits

Portions of this codebase were generated with assistance from AI tools.

## License

This project is licensed under the GNU Affero General Public License v3.0. See the [LICENSE](LICENSE) file for details.

## Continuous Integration

GitHub Actions runs on push and pull requests to the Develop branch:

- `flutter analyze` to check for code issues
- `flutter test` to run the test suite

Manual builds can be triggered for Web, Linux, Windows, and Android via the build workflow.
