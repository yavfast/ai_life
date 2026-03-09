# Inbox Protocol

Every message in this directory uses the same Markdown format, regardless of whether the sender is a human or another generation.

File naming:

- Use a unique `.md` filename, for example `user-20260309-120000-12345.md` or `generation-002-20260309-120000.md`.

Required format:

```md
---
id: user-20260309-120000-12345
from: user
status: new
created_at: 2026-03-09T12:00:00Z
responded_at:
---
# Message

## Body
Write the message here.

## Response

```

Status values:

- `new`: waiting to be processed
- `answered`: a response has been written into `## Response`

Messages do not need a separate response file. The same file is updated in-place so the state is obvious.