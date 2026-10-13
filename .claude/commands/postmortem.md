---
description: Draft a blameless postmortem from incident notes
argument-hint: <incident summary or ticket id>
---

Draft a blameless postmortem for: $ARGUMENTS

Use what is in this conversation (triage output, commands run, timestamps) plus any
linked ticket (use the GitHub MCP server to read the issue if an ID is given).

Write `docs/postmortems/<YYYY-MM-DD>-<slug>.md` with sections:
Summary · Impact (users, duration, SLO burn) · Timeline (UTC) · Root cause ·
What went well · What went wrong · Action items (`owner | action | due | ticket`).

Blameless: describe systems and decisions, never individuals.
