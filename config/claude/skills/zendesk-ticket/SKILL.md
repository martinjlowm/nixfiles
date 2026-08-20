---
name: zendesk-ticket
description: View Zendesk tickets and their full comment threads, download attachments for inspection. Use when investigating support tickets, reading customer conversations, or fetching files attached to Zendesk tickets.
version: 1.0.0
---

# Zendesk ticket

CLI tool for viewing Zendesk tickets and their full comment threads.

## When to use

Use this skill when:
- Viewing a Zendesk support ticket and its conversation thread
- Investigating customer issues reported via Zendesk
- Fetching attachments (logs, screenshots, config files) from ticket comments
- Piping ticket data into other tools for analysis

## Environment

Three environment variables are required:

| Variable | Description | Configured |
|----------|-------------|------------|
| `ZENDESK_SUBDOMAIN` | Zendesk subdomain (`factbird`), overridden when a URL is passed | Yes, in sessionVariables |
| `ZENDESK_EMAIL` | Agent email (`mj@factbird.com`) | Yes, in sessionVariables |
| `ZENDESK_API_TOKEN` | API token | No, must be set per session or sourced from a secret manager |

**If `ZENDESK_API_TOKEN` is not set**, you MUST use the AskUserQuestion tool to ask the user for their Zendesk API token before running any zendesk-ticket commands. Once provided, export it in the shell:

```bash
export ZENDESK_API_TOKEN="<token from user>"
```

Do NOT proceed with API calls without a valid token. They fail with 401 Unauthorized.

Base URL: `https://factbird.zendesk.com`

## CLI usage

Accepts either a numeric ticket ID or a full Zendesk agent URL:

```bash
# By ticket ID
zendesk-ticket 12345

# By Zendesk URL (subdomain extracted automatically, query params ignored)
zendesk-ticket 'https://factbird.zendesk.com/agent/tickets/18000?brand_id=360000686657'

# Include internal/private notes
zendesk-ticket 12345 --internal

# Output raw JSON (for piping into jq, scripts, etc.)
zendesk-ticket 12345 --json
```

When a URL is provided, the subdomain is parsed from the hostname and overrides `ZENDESK_SUBDOMAIN`. This means `ZENDESK_SUBDOMAIN` is only required when passing a bare ticket ID.

## Output format

The default text output renders:
- A header box with ticket ID and subject
- A metadata line with status, priority, requester ID, assignee ID, created and updated timestamps, and tags
- Each comment separated by a divider, showing `[Public]` or `[Internal Note]`, author ID, timestamp, and the plain-text body

The `--json` flag emits a single JSON object:
```json
{
  "ticket": { ... },
  "comments": [ ... ]
}
```

## Working with attachments

Comments in the Zendesk API include an `attachments` array. Each attachment object has:

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Attachment ID |
| `file_name` | string | Original filename |
| `content_url` | string | Direct download URL |
| `content_type` | string | MIME type, such as `image/png` or `application/pdf` |
| `size` | integer | Size in bytes |

### Listing attachments

```bash
zendesk-ticket 12345 --json | jq '
  .comments[]
  | select(.attachments | length > 0)
  | {
      comment_id: .id,
      author: .author_id,
      created: .created_at,
      attachments: [.attachments[] | {name: .file_name, type: .content_type, size: .size, url: .content_url}]
    }
'
```

### Downloading attachments

The `content_url` from the JSON output can be fetched directly with curl. Authentication is required.

```bash
AUTH="${ZENDESK_EMAIL}/token:${ZENDESK_API_TOKEN}"

# Download a single attachment by its content_url
curl -sf -u "$AUTH" -o "filename.png" "CONTENT_URL"

# Download all attachments from a ticket into a directory
mkdir -p /tmp/zendesk-12345
zendesk-ticket 12345 --json | jq -r '
  .comments[].attachments[]
  | "\(.content_url)\t\(.file_name)"
' | while IFS=$'\t' read -r url name; do
  curl -sf -u "$AUTH" -o "/tmp/zendesk-12345/${name}" "$url"
  echo "Downloaded: ${name}"
done
```

### Processing attachments

After downloading all attachments for a ticket, you MUST process and inspect them by file type. Do not wait for the user to ask. Examine every attachment.

Processing rules by file type:

- Images (png, jpg, gif, bmp, webp): read them directly with the Read tool, since Claude is multimodal. Describe what you see.
- PDFs: use the Read tool with the `pages` parameter. Summarize the contents.
- Log files and text (log, txt, csv, json, xml): use the Read tool, or Grep for specific patterns. Highlight errors and anomalies.
- Archives (zip, tar.gz): extract with `tar` or `unzip`, then inspect the contents recursively.
- Video files (mp4, mov, avi, mkv, webm, m4v, 3gp): **extract frames with ffmpeg** for visual context (see below).

### Extracting frames from video attachments

When a ticket has video attachments, use ffmpeg to extract representative frames so you can see what the video shows. Customers often demonstrate an issue with a screen recording, and the frames are the only way to read it.

Standard extraction, evenly spaced frames across the video:

```bash
TICKET_DIR="/tmp/zendesk-12345"
VIDEO="${TICKET_DIR}/screen_recording.mp4"
FRAMES_DIR="${TICKET_DIR}/frames_screen_recording"
mkdir -p "$FRAMES_DIR"

# Get video duration in seconds
DURATION=$(ffprobe -v error -show_entries format=duration \
  -of default=noprint_wrappers=1:nokey=1 "$VIDEO")

# Extract ~10 evenly spaced frames (1 per 10th of the duration)
INTERVAL=$(echo "$DURATION / 10" | bc -l)
ffmpeg -i "$VIDEO" -vf "fps=1/${INTERVAL}" -frames:v 10 \
  "${FRAMES_DIR}/frame_%03d.png" 2>/dev/null
```

For short videos, under 30 seconds, extract 1 frame per second:
```bash
ffmpeg -i "$VIDEO" -vf fps=1 "${FRAMES_DIR}/frame_%03d.png" 2>/dev/null
```

For long videos, over 5 minutes, extract at most 15 frames to keep context manageable:
```bash
INTERVAL=$(echo "$DURATION / 15" | bc -l)
ffmpeg -i "$VIDEO" -vf "fps=1/${INTERVAL}" -frames:v 15 \
  "${FRAMES_DIR}/frame_%03d.png" 2>/dev/null
```

After extracting frames, read each frame image with the Read tool. Describe what it shows and note anything relevant to the customer's issue: error messages on screen, UI state, unexpected behavior.

Complete workflow for video attachments:

1. Download the video attachment with curl, as shown above
2. Probe the video duration with `ffprobe`
3. Choose the frame extraction strategy from the duration
4. Extract frames to a subdirectory named `frames_<original_filename_without_ext>`
5. View each extracted frame with the Read tool
6. Summarize what the video shows in the context of the ticket

## API reference

The CLI uses two Zendesk API endpoints:

### Show ticket
```
GET /api/v2/tickets/{ticket_id}.json
```
Returns ticket metadata: subject, status, priority, requester, assignee, tags, timestamps. Does **not** include the full comment thread.

### List comments
```
GET /api/v2/tickets/{ticket_id}/comments.json?page[size]=100
```
Returns all comments with cursor-based pagination. Each comment includes `plain_body`, `html_body`, `author_id`, `public` flag, `created_at`, and `attachments` array.

### Show attachment
```
GET /api/v2/attachments/{attachment_id}
```
Returns metadata for a single attachment: `content_url`, `malware_scan_result`, dimensions for images, and the inline flag.

## Tips

- Use `--json | jq` for any programmatic access. The structured output is stable
- Pipe `--json` output to an LLM for summarisation of long threads
- The `author_id` in comments is a Zendesk user ID. Resolve it to a name via `GET /api/v2/users/{id}.json` if needed
- Internal notes (`public: false`) are only visible with `--internal`
- Attachments on internal notes are also only visible with `--internal`
