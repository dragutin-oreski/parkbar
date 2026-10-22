---
name: park
description: End-of-session "park" — write down where the work in this session stands, as one Markdown file per effort in the ParkBar notes folder (plus small actions in todo.md), with the command that resumes this session, so the person can close everything and pick it up cold later. Use when the user says "park this", "park everything", "wrap up", "I'm closing everything", "save my state for later", or "/park".
---

# Park this session

The goal: someone who closes every window now can come back in a week, read one file, and carry on.
Write for that person, in short plain sentences. They will see the result in ParkBar, a menu bar
app that lists one file per effort.

## 1. Find the notes folder

This must match ParkBar exactly, or the app and this skill will look at different folders. Use the
first that applies:

1. The environment variable `PARKBAR_NOTES`, if it is set and not empty.
2. `notesFolder` from the config file, if it is a non-empty string (expand a leading `~`). The config
   file is `config.json` in `$PARKBAR_SUPPORT` when that variable is set and not empty, otherwise
   `~/Library/Application Support/ParkBar/config.json`. Ignore the file if it is missing, cannot be
   read, or is not one valid JSON object; ignore `notesFolder` if it is not a string.
3. `~/Documents/ParkBar`.

From the same config file, read `meLabels` (a list of strings; otherwise `["Decide myself"]`) and use
its first entry wherever this skill says "Decide myself". If `meLabels` is an empty list, the person
has turned own decisions off: write no "Decide myself" block at all.

Inside the folder you need `efforts/` and `todo.md`. If they are missing, create them and say so
in your report. Never write anywhere else in the folder.

## 2. Decide which efforts this session touched

An **effort** is one piece of work the person is carrying; its file name is its name
(`efforts/Checkout redesign.md`). Usually a session touches one effort; sometimes two or three.

List `efforts/` first. If the work continues an existing effort (same name, or its `about` line
describes this work), update that file. Otherwise create a new one with a short, human, stable name:
"Checkout redesign", not "fix-bug-in-checkout-2".

## 3. Write each effort file

### A new effort

Create `efforts/<Effort name>.md` with exactly these four fields, then the prose (step 4):

```markdown
---
about: "<one line: what this effort is>"
next: "<one short line: the very next step>"
updated: <today, YYYY-MM-DD>
resume: "claude --resume ${CLAUDE_SESSION_ID}"
---
```

Do not write `status`, `priority` or `target`. Missing, they mean: active, at the bottom of the
person's order, no target date. The person sets them in ParkBar.

### An existing effort

Change only these fields:

- `updated:` today's date, `YYYY-MM-DD`.
- `next:` one short line, in double quotes.
- `resume:` `"claude --resume ${CLAUDE_SESSION_ID}"`.

Replace a field's **whole value**: its `key:` line plus any indented lines below it that belong to it
(a `|` or `>` block, or list items), all become one `key: "value"` line. Leave every other line of the
fields block exactly as it is. If a field is missing, add it as one line just before the closing
`---`. Escape `"` and `\` inside double quotes as `\"` and `\\`.

The result must still be valid YAML between the two `---` lines. If you are not sure you can change
a field safely (an unusual layout, a key that appears twice, no closing `---`), leave the fields
block alone and tell the person which field you could not update.

Never set or change `priority`, `target` or `status`: those belong to the person, who sets them in
ParkBar. The one exception: if the effort is `status: archived` and this session picked it up again,
set `status: active`.

The resume command reopens this exact session. People who start sessions through their own wrapper
script can change the command prefix in this skill; named sessions work too (start with
`claude -n <name>`, resume with `claude --resume <name>`).

## 4. Write the prose

Below the fields, add what changed in this session. On an existing effort, add new blocks at the end
(above the `refs:` line, if there is one). Do not reword or delete what is already there, except to
tick a question this session answered (`- [ ]` → `- [x]`).

Use these labels, each in bold at the very start of a line and ending in a colon; ParkBar reads them:

```markdown
**Where I am (<d Mon>):** What is done, what is half done, what is blocking. Two to five sentences.

**Clarify with <person>:**
- [ ] A question only that person can answer, phrased so they could answer it cold.

**Decide myself:**
- [ ] A decision only the person can make, with the options if they are known.

**Then:** The next one to three steps, in order.

refs: pointers, not copies: links, ticket keys, file paths, branch names
```

- Leave out a block that would be empty.
- One `Clarify with` block per person or group (`Clarify with Alice + Bob:` for a question both must
  answer). Use the names the person uses.
- Pointers, not copies: link to the ticket, the document or the file instead of pasting its contents.
- ParkBar shows the latest `Where I am` and `Then`, so they must stand on their own.

## 5. Add todos

Small concrete actions go in `todo.md`, one line each, linked to their effort:

```markdown
## Next

- [ ] Write the flag rollout plan → [[Checkout redesign]]

## Waiting

- [ ] Bob — review the index migration → [[Checkout redesign]]
```

- Actions for the person go under `## Next` (create the heading if needed).
- Things someone else owes them go under `## Waiting`, starting with that person's name and ` — `.
- Do not add a line that is already there; tick (`[x]`) one this session finished.
- Leave the rest of `todo.md` exactly as it is.

## 6. Safety

- Never write secrets into the notes: no passwords, tokens, keys, connection strings, or personal
  data about anyone. Point to where such things live instead.
- Change only the files and lines this skill names: the effort files you work on, `todo.md`, and
  `efforts/` or `todo.md` if they are missing. Never rename, move or delete a note.

## 7. Report

End with a short list: each file you created or changed and what you wrote in one line, and the
resume command. Example:

```
Parked:
- efforts/Checkout redesign.md — where I am, 2 questions for Alice + Bob, then; next: "Ship the address form"
- todo.md — 1 action, 1 waiting item
Resume: claude --resume <this session>
```
