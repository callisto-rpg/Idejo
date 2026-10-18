# Idejo Community Platform

A self-hosted community server organised like a forum (categories &rarr; topics &rarr; messages), where every topic is a live conversation powered by **Growing Messages**.

Quick lines sent with `Enter` merge into one **growing message** that stays open for a fixed window (default 45s), so conversations read like an organized forum while feeling as immediate as chat.

## Getting Started

To run the development server in AI Studio:

```bash
npm install
npm run dev
```

The app will be available on port 3000 (`http://0.0.0.0:3000`).

## Core Invariants & Features

- **Growing Messages (GM-01 to GM-14)**:
  - Press `Enter` to send a line and start the 45-second window.
  - Subsequent lines sent with `Enter` within that window merge into the same message as commits.
  - The window is fixed: appends never extend or reset the 45-second countdown timer.
  - Press `Ctrl + Enter` (or `Cmd + Enter`) to finish and close the message early.
  - Press `Shift + Enter` for a multi-line break within your draft.
  - Open messages display a live pencil icon ✏️ and real-time countdown timer.
  - Moderators can force-close an open message at any time.
- **Topics & Categories**:
  - Pinned and locked topics, category permission matrix, inline replies, and thread forking (`TP-09`).
- **Search & Moderation**:
  - Full-text search across topics and messages with category filtering (`SE-01`).
  - Audit log and action tracking for moderators (`MO-03`).
