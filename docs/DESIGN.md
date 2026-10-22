# How ParkBar is built

ParkBar is a Swift package with no third-party dependencies. It has one rule that shapes everything
else: **the notes belong to the person, so the app may change only a few known lines, and must never
lose a save made by anyone else.**

## Targets

| Target | What it is |
|---|---|
| `ParkBarCore` | Everything that is not UI: reading the notes, the rules (late, cold, order, people), the config, and the narrow writes. All the tests are here. |
| `ParkBar` | The menu bar app (SwiftUI `MenuBarExtra`, no Dock icon). Holds an `AppModel` and the views. |
| `ParkBarWidget` | A WidgetKit extension. It reads a small snapshot the app writes; it never reads the notes. |
| `parkbar-cli` | The same reads and writes from a terminal, for scripts and for checking the rules by hand. |

`scripts/bundle.sh` assembles `ParkBar.app` (the app, the widget as an `.appex`, the example notes)
and signs it.

## Reading

`Vault.load(from:config:)` reads the whole notes folder into one value: efforts, todos, agenda lists,
and a list of problems (a file that exists but cannot be read). The panel shows problems instead of
looking empty. Nothing is cached between reads; a folder watcher (FSEvents) reloads on any change,
and a timer moves "today" at midnight.

Each `Effort` keeps the SHA-256 of the bytes it was read from. That hash is what every write checks
against.

Parsing is line based and forgiving. The fields block (`Frontmatter`) understands only `key: value`
lines and carries everything else along untouched. The prose (`EffortBody`) is never rewritten: its
sections and questions are only pointers (line numbers and the exact line text) into the file.

## Writing

`NotesEditor` is the only place that writes. It can set the value of `priority`, `target`, `next` and
`status` (the key's line and any lines that belong to its value become one line), and tick one
checkbox. An edit works out every file's new text first, and writes nothing if any file has changed
since it was read. It writes only to a regular `.md` file directly inside `efforts/`, with symlinks
resolved on both sides: an effort entry that links to `todo.md`, an agenda list or another folder is
refused with a message (or skipped with a notice when a drag only renumbers it).

Each file is written by `NoteFile.replace`, a swap protocol:

1. **Check**: the file on disk still has the expected hash.
2. **Prepare**: write the new text to a pending file in ParkBar's support folder
   (`~/Library/Application Support/ParkBar/pending/<pid>.<random>/`). It must be on the same disk as
   the note, or the write is refused.
3. **Swap**: `renamex_np(RENAME_SWAP)` exchanges the two names in one atomic step. The note now holds
   the new text; the pending path holds what was at the note's path a moment ago.
4. **Verify**: hash what came out. If it is exactly what was read in step 1, delete it: done.
5. **Otherwise swap back**: someone saved between steps 1 and 3. The swap is undone, the write fails
   with "changed on disk", and the pending file is deleted only if it holds exactly ParkBar's text.
   Anything else is kept in `recovery/`.

An edit that spans several files (a drag renumbers priorities) puts back the files it already wrote,
with the same protocol, when a later file fails. A file that cannot be put back is named in the error.

At start, `SafeStorage.reconcile()` looks for pending folders left by a process that is no longer
running and moves what it finds to `recovery/`; the panel shows a notice with a **Show** button.

### Accepted limits

- A process holding the note open across the swap can write into the displaced file after step 4
  hashed it; that write is lost when the file is deleted. Any save-by-rename scheme has this.
- Two external saves, one before the swap and one after, cannot both stay at the note's path. The
  first stays; the second is kept in `recovery/` and named in the error.

Both are pinned by tests (`ExternalSaveMatrixTests`), the first as a known issue.

## Config

`ParkBarConfig` is read from `config.json` in the support folder, key by key: a key with the wrong
type, or an unknown one, is ignored and named in a problem, and the other keys still apply. A file
that exists but cannot be read, or is not one JSON object, gives the defaults plus a problem, and is
never overwritten. The app writes only `notesFolder` (when you choose a folder), merging it into the
file so every other key stays as written; keys it still ignores stay listed as problems.

`NotesSetup` decides what the panel shows: `$PARKBAR_NOTES` (which also stops **Choose folder…**, so
the app and `/park` never point at different folders), else the config's folder, else
`~/Documents/ParkBar`; or, while trying them, the example notes with their own settings.
`$PARKBAR_SUPPORT` moves the support folder; the tests use it, so they never touch your own.

## The widget

The widget is sandboxed and cannot read the notes folder. After every reload the app writes
`snapshot.json` (the top efforts, their next step and target) into the widget's own container, and
asks WidgetKit to redraw only when that list changed. The example notes never reach the widget, and
with `$PARKBAR_SUPPORT` set (a test or development run) the snapshot goes to
`$PARKBAR_SUPPORT/widget/` instead. A click opens `parkbar://effort/<name>`, which
the app turns into "open the panel on that effort".

## The example notes

`examples/notes` doubles as documentation and as the "Try the example notes" button. The app finds
it inside the bundle or in the repo it was built from. Every try replaces the copy in the support
folder with a fresh one whose dates are moved by the days since 22 Oct 2026, so it opens with one
effort due today, one late, one in the future and one cold. It is read with `examples/config.json`;
**Back to my notes** or **Choose folder…** returns to the user's own folder and config at once.

## Snapshots

`ParkBar --snapshot out.png --notes DIR --today YYYY-MM-DD [--tab people] [--detail NAME] [--dark]`
renders the panel to a PNG and exits, without watching or writing anything. The screenshots in
`docs/images` are made this way from the example notes.
