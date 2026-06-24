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

## Phase 2 — Unread Tracking & Social Discovery

- [x] **Unread indicators** — parse `channel_unreads` from WS `Ready` payload; show dot on channel tiles in `ChannelPanel`; bold channel name
- [x] **Mention badge** — count unread `@me` mentions per channel; red badge number
- [x] **Mark channel as read** — `PUT /channels/{channelId}/ack/{messageId}` on open / scroll to bottom; handle WS `ChannelAck`
- [x] **Server unread dot** — aggregate per-channel unread state → dot on server icon in server rail
- [x] **Member list panel** — slide-out right panel on desktop; `GET /servers/{serverId}/members`; avatar, nick, role colour, online dot; tap → profile sheet
- [x] **Invite links** — `POST /channels/{channelId}/invites` → share dialog; `POST /invites/{code}` to join; input on home screen
- [x] **@mention autocomplete** — `@` trigger in `_MessageInput` → fuzzy search user cache → insert `<@userId>`

**Relevant files:** `lib/widgets/channel_panel.dart`, `lib/widgets/chat_panel.dart`, `lib/providers/messaging_state.dart`, `lib/providers/server_state.dart`

---

## Phase 3 — Profile & Identity ✅

- [x] **Online status** — dropdown (Online / Idle / Focus / Invisible) → `PATCH /users/@me` `{status:{presence}}`; coloured dot on avatars
- [x] **Custom status text** — text field → `status.text` in same patch; display in user bar / profile sheet
- [x] **Profile bio** — `PATCH /users/@me` `{profile:{content}}`; show in profile bottom sheet
- [x] **Global avatar upload** — image picker → `POST {autumnBase}/avatars` → `PATCH /users/@me` `{avatar: fileId}`
- [x] **Profile banner upload** — same Autumn flow, tag `backgrounds` → `PATCH /users/@me` `{profile:{background: fileId}}`
- [x] **Per-server nickname** — `PATCH /servers/{serverId}/members/@me` `{nickname}`
- [x] **Per-server avatar** — same Autumn flow → `PATCH /servers/{serverId}/members/@me` `{avatar}`
- [x] **View other user profiles** — tap username/avatar → bottom sheet: avatar, banner, bio, status, mutual servers

**Relevant files:** `lib/screens/settings_screen.dart`, `lib/providers/auth_state.dart`, `lib/services/revolt_service.dart`, `lib/models/revolt_user.dart`

---

## Phase 4 — Server Management Basics

- [x] **Role colour on usernames** — `GET /servers/{serverId}/roles`; apply highest-priority role colour to username in bubbles and member list
- [x] **Kick / ban members** — context menu on member tile; `DELETE /servers/{serverId}/members/{userId}` (kick) / `PUT /servers/{serverId}/bans/{userId}` (ban)
- [x] **Create / edit / delete channels** — long-press channel → context menu; `POST /servers/{serverId}/channels`, `PATCH /channels/{channelId}`, `DELETE /channels/{channelId}`
- [x] **Create / edit server** — `POST /servers/create`, `PATCH /servers/{serverId}`; server settings screen
- [x] **Permission management per server** — role-based permission editor; `GET /servers/{serverId}/roles`, `POST /servers/{serverId}/roles`, `PATCH /servers/{serverId}/roles/{roleId}`, `DELETE /servers/{serverId}/roles/{roleId}`; assign/remove roles to members via `PATCH /servers/{serverId}/members/{userId}`; channel permission overrides via `PATCH /channels/{channelId}` `role_permissions` / `user_permissions` fields; server settings screen with roles list, permission toggles per role, and member role assignment UI

---

## Phase 5 — Voice Completeness

- [x] **Participant list not updating on leave** — when a participant leaves the call the tile/list does not remove them; ensure `ParticipantDisconnected` LiveKit event (or equivalent `room.participants` stream) triggers a `setState`/`notifyListeners` in `VoiceState` so `_VoiceChannelView` rebuilds and drops the departed participant. Also affects the **local user** — after leaving/disconnecting, the local client's own entry remains in the sidebar list; clear local participant state and remove the local entry on `Room.disconnected` / `onDisconnected` callback
- [x] **Audio device selection** — enumerate `MediaDevices` (web) / platform channel (native); pass `deviceId` in `AudioCaptureOptions`; store in `VoiceState` / prefs
- [ ] **Camera / video toggle** — `room.localParticipant.setCameraEnabled(bool)`; local video preview tile in `_VoiceChannelView`
- [x] **Noise suppression** — `noiseSuppression: true` wired via `AudioCaptureOptions` on join and device-change; DeepFilterNet neural suppression also integrated and live-togglable
- [x] **Per-participant volume** — context menu (right-click/long-press) on participant row and video tiles; per-source volume (mic vs screen-share-audio); 0–200% range; persisted to prefs; uses `flutter_webrtc` `NativeAudioManagement.setVolume()` instead of buggy web-only `volume_helper`
- [ ] **Notify user on voice device fallback** — When the stored audio input preference is unavailable on join, the app falls back to the first available device and silently overwrites the preference. Show a notification so the user knows their saved device wasn't found.

**Relevant files:** `lib/providers/voice_state.dart`, `lib/widgets/chat_panel.dart` (`_VoiceChannelView`), `lib/screens/settings_screen.dart`

---

## Phase 6 — Polish & Localization

- [ ] **Rework layout for calls** — `RenderFlex overflowed by 46 pixels on the bottom` when a call starts; audit `_VoiceChannelView` column/row constraints, wrap scrollable content in `Expanded`/`Flexible` or `SingleChildScrollView`, ensure the layout doesn't overflow on smaller screens
- [ ] **Theme system** — dark (current) / light / custom accent; persist via `shared_preferences`
- [ ] **Keyboard shortcuts** — `Shortcuts`/`Actions`: Ctrl+K channel search, Escape cancel edit/reply
- [ ] **Rich link embeds** — render `embeds` array from message JSON as OG cards below content
- [ ] **Message search** — search bar in channel header; `GET /channels/{channelId}/messages?query=`
- [ ] **Read marker** — visual line/indicator in chat showing where the last read message is
- [ ] **Mention popup dual-name display** — show server nickname first, then global username if both exist
- [ ] **Localization** — `flutter_localizations` + `intl`; `.arb` files, EN first
- [ ] **Remember email** — Remember email even if password wrong
- [ ] **Remember custom url** — Remember server url even if password wrong

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
