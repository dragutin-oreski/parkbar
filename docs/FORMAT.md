# The notes format

Everything ParkBar shows comes from plain Markdown files in one folder. This page is the full set
of rules; [examples/notes](../examples/notes) follows all of them.

```
<notes folder>/
├── efforts/<Effort name>.md   one file per effort
├── todo.md                    optional
└── <agenda list>.md           optional, one per person, named in the config
```

ParkBar reads every `.md` file directly inside `efforts/` (not in subfolders, not hidden files).
The file name without `.md` is the effort's name; a `[[wiki link]]` to that name links a todo to it.

## The fields block

An effort file starts with a fields block: a line `---`, `key: value` lines, and a closing `---`.
It is a small subset of YAML, the same "properties" block Obsidian shows.

```yaml
---
tags:
  - web
about: "one-page checkout to cut drop-off at the payment step"
status: active
priority: 1
target: 2026-10-22
next: "Ship the new address form behind the flag"
updated: 2026-10-21
resume: "claude --resume checkout-redesign"
---
```

| Key | Value | Notes |
|---|---|---|
| `about` | text | One line shown under the name. |
| `status` | `active`, `archived`, or empty | Missing or empty means active. Any other word is kept as written and the effort is listed under Archived. |
| `priority` | a whole number, or empty | 1 is the top of the drag order. Missing or empty: last, by name. |
| `target` | `YYYY-MM-DD`, or empty | The day you aim to have the next step done. Missing or empty: no target. |
| `next` | text | One short line: the next step. |
| `updated` | `YYYY-MM-DD` | The last day the prose changed. |
| `resume` | text | A command that reopens the session. ParkBar copies it; it never runs it. |

Values may be plain, `"double-quoted"` (JSON-style escapes such as `\"`) or `'single-quoted'` (`''`
for a quote). A ` # comment` after a value is ignored; an empty value, `null` and `~` mean no value.
`|` and `>` blocks are read as text. Other keys (`tags`, lists, anything an editor adds) are allowed
and are never changed.

If the first line is not `---`, or the block never closes, the effort is still listed, marked
"fields unreadable", and ParkBar will not write to it. A key that appears twice is read from its
first line, and ParkBar refuses to change it until you remove the duplicate.

### Dates and states

- **Due**: the target is today. **Late**: the target has passed. The menu bar number counts both.
- **Cold**: active, no target, and `updated` more than `coldAfterDays` days ago (14 by default). Cold
  efforts fold away under the main list. An effort without `updated` is never cold.
- Making an archived effort active puts it at the bottom of the drag order; if it would be cold,
  ParkBar says so.

## The prose

Everything below the fields block is yours. ParkBar looks for **labels**: a bold phrase at the very
start of a line, ending in a colon.

| Label | What ParkBar does with it |
|---|---|
| `**Where I am:**` | Shows the last one on the effort. |
| `**Then:**` | Shows the last one as the plan. |
| `**Clarify with <people>:**` | Its items are questions for those people. |
| `**Decide myself:**` (the config's `meLabels`) | Its items are your own decisions, listed under `meName`. |
| any other bold label | Kept in the notes; nothing more. |

A label may carry a note in brackets (`**Where I am (22 Oct):**`). For the labels above, the colon
may also follow the bold (`**Then**: …`), or a dash may take its place (`**Clarify with Bob** — before
Friday:`). People in a Clarify label are split on ` + `, ` / `, `,`, ` and ` and ` & `:
`Alice + Bob`, `Alice / Bob`, `Bob, Carol and Alice`. The names end at a bracket or a dash, and a
date at the end (`22 Oct`, `Oct 22`, `2026-10-22`) is not a name, so `Clarify with Bob (by Friday)`,
`Clarify with Alice and Bob 22 Oct` and `Clarify with Sam Lee — before the release` name Bob; Alice
and Bob; and Sam Lee. Other numbers stay: `Clarify with Team 2` names Team 2.

### Questions

Under a Clarify or Decide label, each checkbox at the start of a line is one question:

```markdown
**Clarify with Alice + Bob:**
- [ ] Do we keep guest checkout in the first release, or require an account?
- [ ] Which payment errors should stay on the page instead of sending people back
      to the cart?
- [x] Is the flag on for staff accounts?
```

- An indented line continues the question above it; blank lines between questions are fine.
- The list ends at the next label, or at a line of ordinary text starting in column 0.
- A table (`| … |`) or a code block between questions does not end the list and is not a question.
- Ticked questions (`[x]`) are shown done and left out of the People tab.

Text right after the label, up to the first blank line, holds **inline questions** split on ` · `.
They are shown, but there is no checkbox to tick:

```markdown
**Clarify with Carol:** tone for the trial-ending email · do we send on weekends · who signs them
```

If that text ends with a colon (`**Clarify with Bob** — before the load test:`), it only introduces
the checkbox list below.

### Code, and refs

Nothing inside a fenced code block (` ``` ` or `~~~`) is ever read as a label, question or refs line.
An unclosed fence runs to the end of the file, as most editors show it.

A line starting with `refs:` holds pointers (links, ticket keys, file names). ParkBar shows it as
written.

## todo.md

```markdown
## Next

- [ ] Write the flag rollout plan → [[Checkout redesign]]
- [x] ~~Collect last month's support tickets~~ done → [[Pricing page copy]]

## Waiting

- [ ] Bob — review the index migration → [[Search speed-up]]
```

- Each checkbox line is a todo; the `## ` heading above it is its section (`Inbox`, `Next`,
  `Waiting`, `Someday`, or any other).
- `[[Name]]`, `[[Name|shown text]]` and `[[Name#heading|shown text]]` link a todo to an effort; open
  linked todos are shown on that effort. A trailing `→ [[…]]` is hidden when the todo is shown.
- An open todo under `## Waiting` that starts with a name and ` — ` (one to three words, capitalised)
  is something that person owes you; it shows on their page in the People tab.
- ParkBar never writes to `todo.md`.

## Agenda lists

A running list of topics to go through with one person, shown read-only on their page. Name each
file in the config's `agendaLists`:

```markdown
# Bob — things for our Friday catch-up

## Waiting on Bob

- **Index build window** — day or night, and who is on call.
- **Load-test budget**: how many machines we can borrow for an hour.
```

Each `## ` heading is a group; each top-level `- ` bullet is one topic, titled by its first bold
phrase (or its whole first line). ParkBar never writes to agenda lists.

## What ParkBar writes

Only in regular `.md` files directly inside `efforts/` (an entry that is a symlink must resolve to
one), and only this:

- The value of `priority`, `target`, `next` or `status` in the fields block. Setting a field replaces
  its **whole value**: the key's line, plus every line that belongs to it (the indented lines of a `|`
  or `>` block, or the items of a list under the key), become one `key: value` line. Comment lines
  between a list's items stay, just below it. A missing field is added as one new line just before
  the closing `---`. `next` is always written double-quoted.

  ```yaml
  next: |                      next: "Email Bob"
    Call Bob           →       custom:
    Bring the draft              - kept as it was
  custom:
    - kept as it was
  ```

- The `[ ]` or `[x]` of one question checkbox, after checking that the line still reads exactly as it
  did when you clicked it.

Every other byte of the file, line endings included, stays as it was. A symlinked entry that resolves
to anything else (`todo.md`, an agenda list, a file outside `efforts/`) is listed but never written.

## A new effort

The smallest file ParkBar reads is a fields block with no `status`, `priority` or `target`, which is
what `/park` writes for a new effort:

```yaml
---
about: "one line"
next: "the next step"
updated: 2026-10-22
resume: "claude --resume <session>"
---
```

It is active, at the bottom of the drag order, with no target. The first drag or date you set adds
the missing line.
