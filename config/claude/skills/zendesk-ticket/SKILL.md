---
name: zendesk-ticket
description: View a Zendesk ticket with its full comment thread and download its attachments for inspection. Use when investigating a support ticket or reading a customer conversation.
---

# Zendesk ticket

`zendesk-ticket` prints a ticket and its comment thread.

## Confidentiality

Ticket content is customer data. Keep it on this machine: never paste it into a third-party
tool or service without the user's explicit confirmation, and never copy customer names,
contact details or the conversation into a PR, issue or commit. Describe the problem in the
product's terms and link the ticket.

## Environment

| Variable | Value | Set by |
|----------|-------|--------|
| `ZENDESK_SUBDOMAIN` | `factbird`; a URL argument overrides it | sessionVariables |
| `ZENDESK_EMAIL` | `mj@factbird.com` | sessionVariables |
| `ZENDESK_API_TOKEN` | API token | per session, or a secret manager |

Without `ZENDESK_API_TOKEN`, calls fail with 401. In an interactive session, ask the user for
the token and `export ZENDESK_API_TOKEN=<token>`. A headless session has nobody to ask, so stop
and say in the final message that the token is missing.

## CLI usage

```bash
zendesk-ticket 12345
zendesk-ticket 'https://factbird.zendesk.com/agent/tickets/18000?brand_id=360000686657'
zendesk-ticket 12345 --internal   # include internal notes and their attachments
zendesk-ticket 12345 --json       # {"ticket": {...}, "comments": [...]}, for jq
```

A URL's hostname sets the subdomain. The text output shows the subject, a metadata line
(status, priority, requester, assignee, timestamps, tags), then each comment marked `[Public]`
or `[Internal Note]` with its author id. Resolve an author id with
`GET /api/v2/users/{id}.json` when the name matters.

## Attachments

Each comment's `attachments` array holds `file_name`, `content_url`, `content_type` and
`size`. Download into the session's scratchpad directory, not `/tmp`:

```bash
DIR="<scratchpad>/zendesk-12345"
AUTH="${ZENDESK_EMAIL}/token:${ZENDESK_API_TOKEN}"
mkdir -p "$DIR"
zendesk-ticket 12345 --json | jq -r '
  .comments[].attachments[]
  | "\(.content_url)\t\(.file_name)"
' | while IFS=$'\t' read -r url name; do
  curl -sf -u "$AUTH" -o "$DIR/${name}" "$url"
done
```

Inspect every attachment without waiting to be asked:

- **Images:** read them with the Read tool and describe what they show.
- **PDFs:** Read with the `pages` parameter.
- **Logs and text:** Read or Grep; point out errors and anomalies.
- **Archives:** extract with `tar` or `unzip` and inspect the contents.
- **Video:** customers often record the issue, and frames are the only way to read it.
  Extract about ten evenly spaced frames (at most 15 for a long video), read each, and
  summarise what the recording shows:

  ```bash
  V="$DIR/recording.mp4"; F="$DIR/frames_recording"; mkdir -p "$F"
  D=$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$V")
  ffmpeg -i "$V" -vf "fps=10/${D}" -frames:v 10 "$F/frame_%03d.png" 2>/dev/null
  ```

## Calling the API directly

The CLI reads `GET /api/v2/tickets/{id}.json` and
`GET /api/v2/tickets/{id}/comments.json?page[size]=100`. When you fetch the comments with curl,
pass `-g`, here and on the `links.next` URL that carries `page[after]`. curl otherwise reads
`[` as a glob range and aborts with `CURLE_URL_MALFORMAT`.
