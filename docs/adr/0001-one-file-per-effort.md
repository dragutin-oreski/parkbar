# One file per effort, with editable fields at the top

ParkBar has to change an effort's priority, target date and status without ever disturbing the prose
around it. So each effort lives in its own Markdown file under `efforts/`, with a small block of
fields at the top (about, status, priority, target, next, updated, resume) and free prose below. The
app changes a field by replacing its whole value (the key's line and any lines that belong to it) with
one `key: value` line; every other line, and all the prose, stays as written. Todos stay in one `todo.md`, which the app
only reads.

## Considered options

- **All efforts on one page, one section each**: easy to read in any editor, but archived sections
  pile up, and a drag would rewrite many lines of one large shared file, so a conflicting save is far
  more likely to hit the lines being changed.
- **A settings file only the app owns** (priorities and dates keyed by effort name): the notes would
  never be touched, but renaming an effort would silently drop its priority and date, and other tools
  could not see or sort by them.

## Consequences

- A file is the unit of work: renaming the file renames the effort, and `[[wiki links]]` in todos
  follow the name.
- The fields are ordinary YAML properties, so editors such as Obsidian can show and filter them too.
- The `/park` skill writes only prose, `next`, `updated` and `resume`. Priority, target and status are
  the person's, set in ParkBar or by hand; the skill touches status only to make an archived effort
  active again.
