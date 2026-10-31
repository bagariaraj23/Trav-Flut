## Summary

Updates the Flutter theme so the brand color is a single blue pair, makes Discover search cover people and trips, and brings trip chats in line with group chats. Back from a chat returns to the screen that opened it.

**Branch:** `feat-ui-warm-polish` · **Base:** `feat-api-db-optimizations` (PR #52)  
**Head:** `2474db4`  
**PR:** https://github.com/bagariaraj23/Trav-Flut/pull/51

## Changes Made

### Theme

Light mode stays ink and white, with a short blue edge on brand washes. Dark mode uses the blue gradient into ink. Status colors are unchanged: live green, upcoming amber, ended red, and like rose.

| Token | Value | Role |
| --- | --- | --- |
| `accent` | `#1D6FE8` | Light secondary, chips, filled actions |
| `accentDark` | `#6AA8FF` | Dark secondary and the second gradient stop |
| `ink` | `#1C1917` | Light primary and titles |
| `cream` | `#FAF8F4` | Light scaffold and `onPrimary` |

Retint the app by changing `accent` and `accentDark` in `mobile/lib/utils/app_theme.dart`. Washes, soft accents, and gradients follow that pair. Avatar hues that are not the brand stay distinct.

### Discover

Search matches people and trips. An empty field restores the browse feed instead of showing “No trips found”. The All pane previews a few people and trips, with View all. People and Trips chips open the full lists.

### Chat

*   A trip chat is named after the trip. Tapping the title or the info icon opens chat details for groups and trip chats. A direct message still opens the other person’s profile.
*   Every message has a press ripple. Edit and delete stay available only on your own message, for 15 minutes, and not after it is deleted.
*   Trip chat details include add member, promote, remove, leave, rename, and photo, with the same admin rules as a group (including the 16-person cap on a manual add).
*   Leaving the chat does not remove you from the trip. The next trip sync does not put you back. Leaving the trip, or being removed from it, still removes you from the chat.
*   Back from Messages returns to the conversation list. Back from a trip’s chat button returns to that trip. Back from chat details returns to the chat.

## How to Test

```bash
cd mobile && flutter test \
  test/utils/warm_theme_test.dart \
  test/widgets/chat_avatar_test.dart \
  test/widgets/trip_cover_placeholder_test.dart \
  test/widgets/like_button_test.dart
```

Manual:

*   Light and dark mode: buttons and chips use the blue accent. Live, upcoming, ended, and likes keep their own colors.
*   Discover: search `ra`, confirm a few people and trips, then View all. Clear the field and confirm the browse feed returns.
*   Open a trip chat from the trip. The name is the trip title. Chat details can add, remove, promote, and leave. Leave the chat, reopen the trip, and confirm you are still on the trip and still out of the chat.
*   From Messages, open a chat and press back. You should land on Messages, then home. From a trip, back should land on the trip.

## Notes for Reviewers

*   This PR is stacked on [PR #52](https://github.com/bagariaraj23/Trav-Flut/pull/52). `main` was merged in at `49d8980` after PR #55.
*   Someone who left the chat and is later added back to the trip is not put back in the chat automatically. An admin adds them from chat details.
*   Review notes: `PR_docs/PR51_COMPLETE_REVIEW.md`.

## Related

*   Stacked on: [PR #52](https://github.com/bagariaraj23/Trav-Flut/pull/52) — API and database performance.
*   Merged dependency: [PR #50](https://github.com/bagariaraj23/Trav-Flut/pull/50) — trip expense ledger.
*   Merged into this branch: [PR #55](https://github.com/bagariaraj23/Trav-Flut/pull/55).
