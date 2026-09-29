---
name: coaching
description: "Toggle English coaching for the current session (📚 block after replies). Default at session start: OFF"
---

# English coaching

Toggle English coaching for the current session. Default at session start: OFF.

Usage: /coaching [on|off|status]

## Background

"English coaching" is the `📚 English coaching` block normally appended at the END of replies to Mike's messages that contain substantial English (see memory `feedback_english_teacher_mode` for the full Original/Better/Why/Level + score + Strength/Watch format, the zettelkasten archiving rule, and the recurring-pattern tracker).

This command controls whether that block is produced. It is **session-scoped**: the state lives in conversation context only — it is NOT written to any file — so every new session starts with coaching **OFF**.

## Instructions

Read the argument (`$ARGUMENTS`). If empty, treat it as a toggle of the current session state.

### `on` (or toggle when currently OFF)
- Enable English coaching for the remainder of this session.
- From now on, after each technical reply to a Mike message with substantial English (>5 English words; skip pure-Ukrainian, code, paths, IDs), append the `📚 English coaching` block exactly as specified in `feedback_english_teacher_mode`.
- Print: `📚 English coaching: ON for this session`
- If the message that invoked `/coaching on` itself contains substantial English, you MAY coach it now.

### `off` (or toggle when currently ON)
- Disable English coaching. Stop appending the `📚 English coaching` block.
- Print: `📚 English coaching: OFF`

### `status`
- Report whether coaching is currently ON or OFF in this session, and remind Mike it defaults to OFF each new session.
- Print: `📚 English coaching: <ON|OFF> (default OFF each session — toggle with /coaching on|off)`

## Notes

- Default is OFF — if Mike has not run `/coaching on` this session, do not coach.
- Do not persist the state anywhere; it must reset to OFF on the next session.
