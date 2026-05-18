# Fluttering Ermine — Todo / Handoff

> Flutter client for the Stoatchat (Revolt-compatible) server at `/home/noobs/stoatchat`.
> Pick up from here. Phase 1 is mostly done; start at the first unchecked item.

---

## Phase 1 — Core Messaging Completeness ✅/🔄

- [x] Message context menu — right-click (desktop) / long-press (touch); items: Reply, Edit (own), Copy, Delete (own)
- [x] Message editing — inline edit field in `MessageBubble`; Escape cancels, Enter commits; `PATCH /channels/{id}/messages/{id}`
- [x] Message deletion — confirm dialog → `DELETE /channels/{id}/messages/{id}`
- [x] Reply to message — reply bar above input, reply preview quote in bubble; `replies` field on `RevoltMessage`
- [x] Typing indicators — `BeginTyping` WS pulse (debounced 2.5 s); `TypingStart`/`TypingStop` handlers; typing row in `_MessageInput`
- [x] **Emoji reactions** — React item in context menu → emoji picker popup; reaction chips below message body
  - `PUT /channels/{channelId}/messages/{messageId}/reactions/{emoji}` (add)
  - `DELETE /channels/{channelId}/messages/{messageId}/reactions/{emoji}` (remove own)
  - Add `reactions: Map<String, int>` to `RevoltMessage.fromJson`
  - WS event `MessageReact` / `MessageUnreact` updates the map
  - Relevant files: `revolt_message.dart`, `revolt_service.dart`, `messaging_state.dart`, `message_bubble.dart`
- [x] **File / image attachment upload**
  - Add `file_picker` to `pubspec.yaml` (not present yet)
  - Pick file → `POST https://{autumnBase}/attachments` (multipart) → get `id` back
  - Pass `attachments: [id]` in `POST /channels/{channelId}/messages`
  - Show upload progress indicator in `_MessageInput` (clip-icon button left of text field)
  - Relevant files: `revolt_service.dart`, `chat_panel.dart`

---

## Phase 2 — Profile & Identity

- [ ] **Online status** — dropdown (Online / Idle / Focus / Invisible) → `PATCH /users/@me` `{status:{presence}}`; coloured dot on avatars
- [ ] **Custom status text** — text field → `status.text` in same patch; display in user bar / profile sheet
- [ ] **Profile bio** — `PATCH /users/@me` `{profile:{content}}`; show in profile bottom sheet
- [ ] **Global avatar upload** — image picker → `POST {autumnBase}/avatars` → `PATCH /users/@me` `{avatar: fileId}`
- [ ] **Profile banner upload** — same Autumn flow, tag `backgrounds` → `PATCH /users/@me` `{profile:{background: fileId}}`
- [ ] **Per-server nickname** — `PATCH /servers/{serverId}/members/@me` `{nickname}`
- [ ] **Per-server avatar** — same Autumn flow → `PATCH /servers/{serverId}/members/@me` `{avatar}`
- [ ] **View other user profiles** — tap username/avatar → bottom sheet: avatar, banner, bio, status, mutual servers

**Relevant files:** `lib/screens/settings_screen.dart`, `lib/providers/auth_state.dart`, `lib/services/revolt_service.dart`, `lib/models/revolt_user.dart`

---

## Phase 3 — Unread Tracking & Social Discovery

- [ ] **Unread indicators** — parse `channel_unreads` from WS `Ready` payload; show dot on channel tiles in `ChannelPanel`; bold channel name
- [ ] **Mention badge** — count unread `@me` mentions per channel; red badge number
- [ ] **Mark channel as read** — `PUT /channels/{channelId}/ack/{messageId}` on open / scroll to bottom; handle WS `ChannelAck`
- [ ] **Server unread dot** — aggregate per-channel unread state → dot on server icon in server rail
- [ ] **Member list panel** — slide-out right panel on desktop; `GET /servers/{serverId}/members`; avatar, nick, role colour, online dot; tap → profile sheet
- [ ] **Invite links** — `POST /channels/{channelId}/invites` → share dialog; `POST /invites/{code}` to join; input on home screen
- [ ] **@mention autocomplete** — `@` trigger in `_MessageInput` → fuzzy search user cache → insert `<@userId>`

**Relevant files:** `lib/widgets/channel_panel.dart`, `lib/widgets/chat_panel.dart`, `lib/providers/messaging_state.dart`, `lib/providers/server_state.dart`

---

## Phase 4 — Server Management Basics

- [ ] **Role colour on usernames** — `GET /servers/{serverId}/roles`; apply highest-priority role colour to username in bubbles and member list
- [ ] **Kick / ban members** — context menu on member tile; `DELETE /servers/{serverId}/members/{userId}` (kick) / `PUT /servers/{serverId}/bans/{userId}` (ban)
- [ ] **Create / edit / delete channels** — long-press channel → context menu; `POST /servers/{serverId}/channels`, `PATCH /channels/{channelId}`, `DELETE /channels/{channelId}`
- [ ] **Create / edit server** — `POST /servers/create`, `PATCH /servers/{serverId}`; server settings screen

---

## Phase 5 — Voice Completeness

- [ ] **Audio device selection** — enumerate `MediaDevices` (web) / platform channel (native); pass `deviceId` in `AudioCaptureOptions`; store in `VoiceState` / prefs
- [ ] **Camera / video toggle** — `room.localParticipant.setCameraEnabled(bool)`; local video preview tile in `_VoiceChannelView`
- [ ] **Noise suppression** — verify `noiseSuppression: true` in `AudioCaptureOptions` is wired through `VoiceState` → `RoomOptions` (settings toggle exists but may be disconnected)
- [ ] **Per-participant volume** — slider per remote participant; `RemoteParticipant.setVolume(0.0–1.0)`

**Relevant files:** `lib/providers/voice_state.dart`, `lib/widgets/chat_panel.dart` (`_VoiceChannelView`), `lib/screens/settings_screen.dart`

---

## Phase 6 — Polish & Localization

- [ ] **Theme system** — dark (current) / light / custom accent; persist via `shared_preferences`
- [ ] **Keyboard shortcuts** — `Shortcuts`/`Actions`: Ctrl+K channel search, Escape cancel edit/reply
- [ ] **Rich link embeds** — render `embeds` array from message JSON as OG cards below content
- [ ] **Message search** — search bar in channel header; `GET /channels/{channelId}/messages?query=`
- [ ] **Localization** — `flutter_localizations` + `intl`; `.arb` files, EN first

---

## Architecture Notes

### Key files
| File | Purpose |
|---|---|
| `lib/services/revolt_service.dart` | All HTTP + WS calls. API base from `AuthState`. |
| `lib/providers/messaging_state.dart` | Messages, users cache, reply target, typing state. |
| `lib/providers/server_state.dart` | Servers, channels, selected state. |
| `lib/providers/auth_state.dart` | Login, token, current user, base URLs. |
| `lib/providers/voice_state.dart` | LiveKit room, participants, mic/cam. |
| `lib/widgets/chat_panel.dart` | Main chat area, voice tab, `_MessageInput`, `_ReplyBar`, `_TypingIndicator`. |
| `lib/widgets/message_bubble.dart` | `StatefulWidget`; hover bar, context menu, inline edit, reply preview. |
| `lib/widgets/channel_panel.dart` | Channel list, server rail. |
| `lib/models/revolt_message.dart` | `replies: List<String>` field present. |

### Server info
- Stoatchat Rust server: `/home/noobs/stoatchat`
- WS events defined in `crates/core/database/src/events/client.rs` — `EventV1` enum with `#[serde(tag = "type")]`
- Multi-event WS payloads are wrapped in `Bulk { v: Vec<EventV1> }` — already unwrapped in `revolt_service.dart` `connectWebSocket()`

### Packages (pubspec.yaml)
- `http: ^1.2.2`, `web_socket_channel: ^3.0.1`, `provider: ^6.1.2`
- `livekit_client: ^2.7.0` for voice
- `shared_preferences: ^2.3.4`
- **`file_picker` NOT present** — must add before implementing attachment upload

### API conventions
- Auth header: `x-session-token: <token>` (set in `_headers` in `RevoltService`)
- Autumn (file server) base URL: `AuthState.autumnBase`
- API base: `AuthState.apiBase`

---

## Out of Scope
- Bot creation/management
- Webhook configuration
- Server analytics / audit logs
- Spatial audio
- Call recording
- MFA / account security
