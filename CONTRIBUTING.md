# Contributing

## Build and test

```sh
swift build                 # everything
swift test                  # the ParkBarCore tests; they use throwaway folders only
scripts/bundle.sh           # build/ParkBar.app, signed ad-hoc
```

Run the app and the CLI on a copy of the examples, so neither your own notes and settings nor the
tracked example files change:

```sh
TRY=$(mktemp -d) && cp -R examples/notes "$TRY/notes" && cp examples/config.json "$TRY/config.json"
PARKBAR_SUPPORT="$TRY" .build/debug/parkbar-cli --notes "$TRY/notes" --config "$TRY/config.json" list
PARKBAR_SUPPORT="$TRY" PARKBAR_NOTES="$TRY/notes" .build/debug/ParkBar
```

With `PARKBAR_SUPPORT` set, the app also leaves the real widget alone.

Screenshots for the docs come from the snapshot mode (see [docs/DESIGN.md](docs/DESIGN.md)), with
`examples/config.json` copied into a throwaway `PARKBAR_SUPPORT` folder and `--today 2026-10-22`.

## The one rule

**Never write beyond the allowed lines.** ParkBar may change the value of `priority`, `target`,
`next` or `status` in an effort file (the key's line and the lines that belong to its value) and the
box of one question checkbox, through `NotesEditor` and `NoteFile.replace`, and nothing else: no
other line, no file but a regular `.md` directly inside `efforts/`, no rename or delete. A change that needs to write more needs a discussion first, and an update to the "What ParkBar
may write" section of the README.

Every change to how files are read or written comes with a test that checks the exact bytes before
and after (see `changedLines` in the tests), and tests must never touch the real notes or support
folders.

## Style

- Core logic goes in `ParkBarCore` with tests; the app and CLI stay thin.
- No third-party dependencies.
- Comments say why, in plain sentences; keep the words in [GLOSSARY.md](GLOSSARY.md).
