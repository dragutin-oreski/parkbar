# Glossary

The words ParkBar uses, in the code, the docs and the panel.

## Efforts

**Effort**:
One piece of work you are carrying, kept as one file in `efforts/`: a few fields, then your own prose.
_Avoid_: Topic, project, item

**Parking**:
Writing down where an effort stands so you can close the session and pick it up later, cold. The
`/park` skill does it at the end of a Claude Code session.

**Active effort**:
An effort you are still looking at.

**Archived effort**:
An effort you have stopped looking at, finished or not. It can be made active again.
_Avoid_: Done, closed, deleted

**Cold effort**:
An active effort with no target date whose prose has not been updated for more than `coldAfterDays`
days (14 by default). Worked out, never set by hand.
_Avoid_: Stale, old

**Priority**:
An active effort's place in your drag order; 1 is the top and no two active efforts share a number.
_Avoid_: Rank, importance

**Target date**:
The day you aim to have an effort's next step done. **Due** when it is today, **late** once it has
passed.
_Avoid_: Deadline, snooze

**Next step**:
One short line saying what to do next on an effort.

**Updated**:
The last day the effort's prose changed. Reordering or setting a date does not count.

**Resume command**:
The command that reopens the session an effort was parked from, such as `claude --resume <id>`.

**Label**:
A bold phrase at the start of a line in an effort's prose, such as `**Where I am:**`. ParkBar finds
sections by their labels.

## Todos and people

**Todo**:
One small concrete action in `todo.md`.
_Avoid_: Task, action item

**Linked todo**:
A todo that points at an effort with `[[Effort name]]`, shown with that effort.

**Inbox**:
The todos under `## Inbox` in `todo.md`: things to do soon. The open ones are listed at the top of
the Efforts tab and counted in blue in the menu bar.

**Question**:
An item under a `Clarify with <person>` label: something only that person can answer. Under a
`Decide myself` label, something only you can decide.
_Avoid_: Open point

**Waiting item**:
An open todo under `## Waiting` that starts with a person's name: something they owe you.

**Agenda list**:
A running list of topics to go through with one person, named in the config. The word "topic"
belongs here only.

**Me**:
The person your own decisions are listed under; the config's `meName`.

## Writing

**Notes folder**:
The folder holding `efforts/`, `todo.md` and any agenda lists.

**Support folder**:
`~/Library/Application Support/ParkBar` (or `$PARKBAR_SUPPORT`): the config, pending writes,
recovered versions and the example-notes copy. Never inside the notes folder.

**Swap**:
Exchanging the note and the prepared new version in one atomic rename, so the note is never half
written.

**Recovery**:
A version of a note that ParkBar could not prove was safe to delete, kept in the support folder's
`recovery/` and named in the panel.
