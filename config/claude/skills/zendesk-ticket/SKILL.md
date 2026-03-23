---
name: zendesk-ticket
description: View Zendesk tickets and their full comment threads, download attachments for inspection. Use when investigating support tickets, reading customer conversations, or fetching files attached to Zendesk tickets.
version: 1.0.0
---

# Zendesk Ticket Skill

CLI tool for viewing Zendesk tickets and their full comment threads.

## When to Use This Skill

Use this skill when:
- Viewing a Zendesk support ticket and its conversation thread
- Investigating customer issues reported via Zendesk
- Fetching attachments (logs, screenshots, config files) from ticket comments
- Piping ticket data into other tools for analysis

## Environment

Three environment variables are required:

| Variable | Description | Configured |
|----------|-------------|------------|
| `ZENDESK_SUBDOMAIN` | Zendesk subdomain (`factbird`) — overridden when a URL is passed | Yes — in sessionVariables |
| `ZENDESK_EMAIL` | Agent email (`mj@factbird.com`) | Yes — in sessionVariables |
| `ZENDESK_API_TOKEN` | API token | No — must be set per-session or sourced from a secret manager |

**If `ZENDESK_API_TOKEN` is not set**, you MUST use the AskUserQuestion tool to ask the user for their Zendesk API token before running any zendesk-ticket commands. Once provided, export it in the shell:

```bash
export ZENDESK_API_TOKEN="<token from user>"
```

Do NOT proceed with API calls without a valid token — they will fail with 401 Unauthorized.

Base URL: `https://factbird.zendesk.com`

## CLI Usage

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

## Output Format

The default text output renders:
- A header box with ticket ID and subject
- Metadata line: status, priority, requester ID, assignee ID, created/updated timestamps, tags
- Each comment separated by a divider, showing `[Public]` or `[Internal Note]`, author ID, timestamp, and the plain-text body

The `--json` flag emits a single JSON object:
```json
{
  "ticket": { ... },
  "comments": [ ... ]
}
```

## Working with Attachments

Comments in the Zendesk API include an `attachments` array. Each attachment object has:

| Field | Type | Description |
|-------|------|-------------|
| `id` | integer | Attachment ID |
| `file_name` | string | Original filename |
| `content_url` | string | Direct download URL |
| `content_type` | string | MIME type (e.g. `image/png`, `application/pdf`) |
| `size` | integer | Size in bytes |

### Listing Attachments

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

### Downloading Attachments

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

### Processing Attachments

After downloading all attachments for a ticket, you MUST automatically process and inspect them based on file type. Do not wait for the user to ask — proactively examine every attachment.

**Automatic processing rules by file type:**

- **Images** (png, jpg, gif, bmp, webp): Use the Read tool to view them directly (Claude is multimodal). Describe what you see.
- **PDFs**: Use the Read tool with `pages` parameter. Summarize contents.
- **Log files / text** (log, txt, csv, json, xml): Use the Read tool or Grep for specific patterns. Highlight errors or anomalies.
- **Archives** (zip, tar.gz): Extract with `tar` or `unzip`, then inspect contents recursively.
- **Video files** (mp4, mov, avi, mkv, webm, m4v, 3gp): **Extract frames with ffmpeg** for visual context (see below).

### Extracting Frames from Video Attachments

When a ticket contains video attachments, use ffmpeg to extract representative frames so you can visually inspect what the video shows. This is critical for understanding customer-reported issues that are demonstrated via screen recordings.

**Standard extraction — evenly spaced frames across the video:**

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

**For short videos (< 30s) — extract 1 frame per second:**
```bash
ffmpeg -i "$VIDEO" -vf fps=1 "${FRAMES_DIR}/frame_%03d.png" 2>/dev/null
```

**For long videos (> 5min) — extract ~15 frames max to keep context manageable:**
```bash
INTERVAL=$(echo "$DURATION / 15" | bc -l)
ffmpeg -i "$VIDEO" -vf "fps=1/${INTERVAL}" -frames:v 15 \
  "${FRAMES_DIR}/frame_%03d.png" 2>/dev/null
```

After extracting frames, use the Read tool to view each frame image. Describe the visual content and note anything relevant to the customer's issue (error messages on screen, UI state, unexpected behavior, etc.).

**Complete workflow for video attachments:**

1. Download the video attachment using curl (as shown above)
2. Probe the video duration with `ffprobe`
3. Choose frame extraction strategy based on duration
4. Extract frames to a subdirectory named `frames_<original_filename_without_ext>`
5. View each extracted frame with the Read tool
6. Summarize what the video shows in the context of the ticket

## API Reference

The CLI uses two Zendesk API endpoints:

### Show Ticket
```
GET /api/v2/tickets/{ticket_id}.json
```
Returns ticket metadata (subject, status, priority, requester, assignee, tags, timestamps). Does **not** include the full comment thread.

### List Comments
```
GET /api/v2/tickets/{ticket_id}/comments.json?page[size]=100
```
Returns all comments with cursor-based pagination. Each comment includes `plain_body`, `html_body`, `author_id`, `public` flag, `created_at`, and `attachments` array.

### Show Attachment
```
GET /api/v2/attachments/{attachment_id}
```
Returns metadata for a single attachment including `content_url`, `malware_scan_result`, dimensions (for images), and inline flag.

## Tips

- Use `--json | jq` for any programmatic access — the structured output is stable
- Pipe `--json` output to an LLM for summarisation of long threads
- The `author_id` in comments is a Zendesk user ID — resolve to names via `GET /api/v2/users/{id}.json` if needed
- Internal notes (`public: false`) are only visible with `--internal`
- Attachments on internal notes are also only visible with `--internal`
