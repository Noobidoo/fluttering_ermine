# Fluttering Ermine — Post-MVP Roadmap

> MVP tracked in `Todo.md`. This covers Discord-parity features beyond core messaging + voice.

---

## R1 — Markdown & Rich Messages

| Feature | Notes |
|---|---|
| Markdown rendering | Add `flutter_markdown`; bold/italic/strike/code/blockquote in `message_bubble.dart` |
| Spoiler tags (`\|\|text\|\|`) | Custom span builder; tap to reveal |
| Image lightbox | `InteractiveViewer` fullscreen overlay on attachment tap |
| Message pinning | Context menu (mod+); `POST/DELETE /channels/{id}/pins/{msgId}`; pinned banner in header |
| Custom server emoji | Fetch from server object; cache; render `:emojiId:` tokens; show in picker |
| Rich link embeds | Render `embeds[]` from message JSON as OG preview cards |

---

## R2 — Social Graph

| Feature | Notes |
|---|---|
| Friends list | `GET /users/friends`; pending badge; `PUT/DELETE /users/{id}/friend` |
| Friend requests | Incoming / outgoing tabs; WS `UserRelationship` event |
| Group DMs | `group` channel type; create/edit name+icon; add/remove members |
| Open DM from profile | "Message" button → `GET /users/{id}/dm` → navigate |

---

## R3 — Voice Parity

| Feature | Notes |
|---|---|
| Deafen | Mute all remote audio locally; `_isDeafened` in `VoiceState`; headphone icon in voice bar |
| Push-to-talk | PTT mode toggle; hold → `setMicrophoneEnabled(true)`; configurable keybind |
| Screen share viewer | Wire existing `remoteVideoStreams` (screenShareVideo) to fullscreen tile in `_VoiceChannelView` |

---

## R4 — Server Organisation

| Feature | Notes |
|---|---|
| Channel categories | `category` field on channel; collapsible `ExpansionTile` groups in sidebar |
| Role management | Create/edit/delete roles; assign to members; role list in server settings |
| Channel permission overrides | Per-channel role/user allow+deny bitmask; channel edit sheet |

---

## R5 — Notifications

| Feature | Notes |
|---|---|
| Per-channel notification level | All / Mentions / Muted; channel context menu |
| Per-server mute | Suppress all badges for a server |
| Mobile push (Android/iOS) | FCM + APNs; `firebase_messaging`; `POST /push/subscribe` with device token |

---

## R6 — Polish

| Feature | Notes |
|---|---|
| Theme system | Dark / light / custom accent; `shared_preferences` |
| Keyboard shortcuts | Ctrl+K search, Escape cancel, configurable PTT key |
| Message search | Search bar in channel header; `GET /channels/{id}/messages?query=` |
| Localization | `flutter_localizations` + `intl`; `.arb` EN first |

---

## Out of Scope (indefinitely)

- Bot creation / webhook configuration
- Server audit logs / analytics
- Spatial audio
- Call recording
- MFA / account security settings
