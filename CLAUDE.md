# Lapp

A post-it strip that lives on the edge of the side screen. Native AppKit, no dependencies.

## Build

**Never build into this folder.** The checkout lives inside an iCloud-synced `~/Documents`
tree. iCloud stamps `com.apple.FinderInfo` on anything it syncs, `xattr -cr` cannot remove it,
and `codesign` then fails with *"resource fork, Finder information, or similar detritus not
allowed"* — producing a bundle macOS silently refuses to launch. Every build path below is
outside iCloud on purpose.

```bash
./make.sh              # build + sign -> ~/Lapp-build/dist/Lapp.app
./make.sh --install    # the above, then quit + copy to /Applications + relaunch
```

Prefer `--install`. The login item registers whatever path the app launched from, so running
from `~/Lapp-build/dist` would pin login to a build directory.

`make.sh` quits the running copy with `osascript -e 'quit app "Lapp"'` rather than `pkill`, so
`applicationShouldTerminate` flushes the in-progress draft first.

## Data

`~/Lapp/` — also outside iCloud.

| | |
|---|---|
| `current.md` | the live draft, autosaved 800 ms after the last keystroke |
| `notes/` | filed notes, `yyyy-MM-dd-HHmm-slug.md`, YAML front matter (`created`, `filed`) |
| `trash/` | discarded notes, purged at 30 days (once at launch, no timer) |
| `state.json` | the draft's `created` stamp |
| `settings.json` | display, edge, width, appearance, font size, hotkeys, vault |

Opening a note from history *moves* it back onto the pad, so a note is never in two places.
✓ files it again, ✕ bins it.

The 30-day purge reads `contentModificationDate`, and a move preserves it — so `Store.delete`
restamps the file after moving it into `trash/`. Without that, binning a note filed two months
ago would delete it at the very next launch instead of giving it 30 days.

## Shape

The panel is `card + tab`. The card sits **flush** against the screen edge (no outer inset)
and is rounded only on the corners facing into the screen, so it reads as extending out of
the side rather than floating near it. The tab is a 13×50 nub protruding further inward,
vertically centred — click it to minimise, and it is the entire window when minimised
(13 pt wide, so the window must actually shrink; a transparent window would still eat
clicks); both figures live in `ScreenAnchor.Metrics`. Drag it to move the strip to the other
edge or another screen; it snaps to whichever edge you release nearest.
`PadContainerView.layout()` does this by hand — dynamic constraint swapping for two boxes is
more code, not less.

Height is a fraction of `visibleFrame` (default 0.48), vertically centred. Width, height,
opacity, text size and appearance are all sliders in Settings; there are no drag grips.
Opacity is `panel.alphaValue` — the whole window, text included, not just the background.

`Motion.swift` holds the one timing curve and the durations. Animations should be added
there rather than inline, so they all move the same way.

## The minimise swipe

Shrinking the window on its own reads as *vanishing*, not sliding. The trick is in
`AppController.setMinimized`:

- The window's **outer** edge stays pinned while its width animates; the inner edge travels.
- `PadContainerView.swipingCardWidth` holds the card at its full width during the animation
  and lays it out as if expanded, so the card is carried past the window edge and clipped
  there instead of being squashed into nothing.
- Only the **width** is animated. The height change is applied instantly at the end and is
  invisible, because once the card has gone the only thing drawn is the tab and the window
  is transparent everywhere else.
- Sliding the *window* off the screen edge would have been simpler and is wrong: the
  displays are adjacent, so the card would reappear on the neighbouring screen.

`suppressReposition` stops the settings-changed observer from fighting the controller for
the frame while this runs.

## Things that will bite

- **`RegisterEventHotKey` is not a conflict check.** It returns `noErr` for combinations macOS
  already owns — ⌘Space registers "successfully" and then never fires. Conflict detection lives
  in `SystemHotkeys.swift`: a table of macOS defaults, corrected by the entries the user has
  actually changed in `com.apple.symbolichotkeys`. Defaults are *not* written to that domain,
  which is why the table has to exist. A third-party app holding a combination cannot be
  detected by any public API — the UI warns, it does not promise.
- **The panel must not activate the app.** `.nonactivatingPanel` + `canBecomeKey = true` +
  `.accessory` activation policy. Never call `NSApp.activate()`. Escape returns focus by
  re-activating the `NSRunningApplication` captured before the pad took focus.
- **`LSUIElement` apps still need a main menu** — it is what routes ⌘C/⌘V/⌘Z to the text view.
- **Nothing polls.** Idle CPU must stay at 0.0%; if it doesn't, something is polling and
  that's the bug. The only `Timer` in the app is the one-shot in `PadRootView.flash` that
  fades the status line out; a *repeating* timer anywhere is the smell to look for.
- `NSTextStorageDelegate` restyles only the paragraphs an edit touched, never the document.
- List continuation lives in `ListContinuation.swift` as a pure function on (line, caret) so
  it can be tested without driving the UI — `LappTextView.insertNewline` is only the hook.
  It goes through `insertText`, which is what puts it in the undo stack.
- **`SettingsData` decodes key by key on purpose.** Swift's synthesised `init(from:)` throws
  on a missing key *even when the property has a default*, so adding one field would silently
  reset every setting the user has. Any new field must go in that hand-written initialiser.

## Layout

`Sources/Lapp/` — one file per concern; `main.swift` holds `AppController`, which wires the
panel, the store, the hotkeys and the login item together.
