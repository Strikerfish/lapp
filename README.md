# Lapp

A post-it strip that lives on the edge of your side screen. Press a key, write the thing down,
press another key, get back to what you were doing.

Native AppKit, no dependencies, no menu bar icon, no window to manage. Idle CPU is 0.0% —
nothing in it polls.

## What it does

- **Always there.** A narrow strip pinned flush to the left or right edge of a chosen display,
  floating above everything and visible on every Space. Drag its tab to move it to the other
  edge or to another screen.
- **Never steals focus.** It is a non-activating panel: it takes your keystrokes without making
  Lapp the frontmost app, so the thing you were working in stays where it was. Escape hands
  focus straight back.
- **Markdown as you type.** Headings, lists, quotes, bold, italic, code and checkboxes are
  styled in place. The text itself is never rewritten, so what you see is exactly what lands on
  disk. Lists carry on to the next line and end themselves when you leave an item empty, the way
  Obsidian does.
- **Files to plain markdown.** ✓ files the pad into history, ✕ bins it. History is a searchable
  list; opening a note *moves* it back onto the pad, so a note is never in two places at once.
- **Sends to Obsidian.** Pick a vault and a folder — read from Obsidian's own config, so it's a
  dropdown, not a path to type — and one shortcut writes the note there and opens it.
- **One key to get to it.** ⌥Space by default, and every shortcut is rebindable. Because
  `RegisterEventHotKey` reports success for combinations macOS has already claimed, Settings
  checks your actual system shortcuts and warns you before a binding silently does nothing.

## Requirements

macOS 14 or later, and Swift 6 to build it.

## Build

```bash
./make.sh              # build + sign -> ~/Lapp-build/dist/Lapp.app
./make.sh --install    # the above, then quit + copy to /Applications + relaunch
```

Prefer `--install`: the login item registers whatever path the app launched from, so running it
out of a build directory would pin login to that directory.

Both paths build **outside** `~/Documents` on purpose. iCloud stamps `com.apple.FinderInfo` on
anything it syncs, `xattr -cr` cannot remove it, and `codesign` then rejects the bundle with
*"resource fork, Finder information, or similar detritus not allowed"* — producing an app macOS
silently refuses to launch. If you keep this repo outside iCloud, that constraint doesn't apply
to you, but the script does no harm either way.

The app is signed ad-hoc, so the first launch needs the usual right-click → Open.

## Your notes

Everything lives in `~/Lapp/` as plain files. If the app ever dies, your notes are just markdown.

| | |
|---|---|
| `current.md` | the live draft, autosaved 800 ms after the last keystroke |
| `notes/` | filed notes, `yyyy-MM-dd-HHmm-slug.md`, with `created` / `filed` front matter |
| `trash/` | binned notes, purged after 30 days |
| `settings.json` | display, edge, size, appearance, hotkeys, vault |

## Default shortcuts

| | |
|---|---|
| ⌥Space | focus the pad (global) |
| ⌘↩ | file the note |
| ⌘⌫ | discard it |
| ⌘L | history |
| ⌘, | settings |
| ⌘⇧O | send to Obsidian |
| ⎋ | hand focus back to the app you came from |

All rebindable in Settings. Everything but ⌥Space only fires while the pad has focus.

## Layout

`Sources/Lapp/`, one file per concern. `main.swift` holds `AppController`, which wires the
panel, the store, the hotkeys and the login item together. `CLAUDE.md` is the working notes:
why the minimise animation is built the way it is, and which parts will bite you if you change
them.
