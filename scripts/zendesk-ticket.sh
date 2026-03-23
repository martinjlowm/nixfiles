# Usage: zendesk-ticket <ticket-id-or-url> [--internal] [--json]
#   zendesk-ticket 12345                                                    - show ticket thread
#   zendesk-ticket https://factbird.zendesk.com/agent/tickets/18000         - from URL
#   zendesk-ticket 'https://factbird.zendesk.com/agent/tickets/18000?...'   - query params ignored
#   zendesk-ticket 12345 --internal                                         - include internal notes
#   zendesk-ticket 12345 --json                                             - output raw JSON
#
# Environment variables:
#   ZENDESK_SUBDOMAIN  - your Zendesk subdomain (e.g. "mycompany") — overridden by URL subdomain
#   ZENDESK_EMAIL      - agent email address
#   ZENDESK_API_TOKEN  - API token (used as email/token auth)
set -euo pipefail

TICKET_ID=""
SUBDOMAIN_OVERRIDE=""
SHOW_INTERNAL=false
RAW_JSON=false

# Parse a Zendesk URL like https://<subdomain>.zendesk.com/agent/tickets/<id>?...
parse_zendesk_url() {
  local url="$1"
  if [[ "$url" =~ ^https?://([^.]+)\.zendesk\.com/agent/tickets/([0-9]+) ]]; then
    SUBDOMAIN_OVERRIDE="${BASH_REMATCH[1]}"
    TICKET_ID="${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

for arg in "$@"; do
  case "$arg" in
    --internal) SHOW_INTERNAL=true ;;
    --json) RAW_JSON=true ;;
    --help|-h)
      echo "Usage: zendesk-ticket <ticket-id-or-url> [--internal] [--json]"
      echo ""
      echo "Display a Zendesk ticket and its full comment thread."
      echo ""
      echo "Accepts a numeric ticket ID or a full Zendesk URL:"
      echo "  zendesk-ticket 12345"
      echo "  zendesk-ticket https://factbird.zendesk.com/agent/tickets/18000"
      echo "  zendesk-ticket 'https://factbird.zendesk.com/agent/tickets/18000?brand_id=...'"
      echo ""
      echo "Options:"
      echo "  --internal   Include internal/private notes"
      echo "  --json       Output raw JSON instead of formatted text"
      echo "  --help       Show this help"
      echo ""
      echo "Environment variables:"
      echo "  ZENDESK_SUBDOMAIN  Your Zendesk subdomain (overridden when using a URL)"
      echo "  ZENDESK_EMAIL      Agent email address"
      echo "  ZENDESK_API_TOKEN  API token"
      exit 0
      ;;
    *)
      if [ -z "$TICKET_ID" ]; then
        if [[ "$arg" =~ ^[0-9]+$ ]]; then
          TICKET_ID="$arg"
        elif parse_zendesk_url "$arg"; then
          : # TICKET_ID and SUBDOMAIN_OVERRIDE set by parse_zendesk_url
        else
          echo "Error: Expected a ticket ID or Zendesk URL, got: $arg" >&2
          exit 1
        fi
      else
        echo "Error: Unknown argument: $arg" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$TICKET_ID" ]; then
  echo "Error: Ticket ID or URL is required" >&2
  echo "Usage: zendesk-ticket <ticket-id-or-url> [--internal] [--json]" >&2
  exit 1
fi

# URL-provided subdomain takes precedence over env var
if [ -n "$SUBDOMAIN_OVERRIDE" ]; then
  ZENDESK_SUBDOMAIN="$SUBDOMAIN_OVERRIDE"
fi

if [ -z "${ZENDESK_SUBDOMAIN:-}" ]; then
  echo "Error: ZENDESK_SUBDOMAIN is not set (and no URL provided)" >&2
  exit 1
fi

if [ -z "${ZENDESK_EMAIL:-}" ]; then
  echo "Error: ZENDESK_EMAIL is not set" >&2
  exit 1
fi

if [ -z "${ZENDESK_API_TOKEN:-}" ]; then
  echo "Error: ZENDESK_API_TOKEN is not set" >&2
  exit 1
fi

BASE_URL="https://${ZENDESK_SUBDOMAIN}.zendesk.com"
AUTH="${ZENDESK_EMAIL}/token:${ZENDESK_API_TOKEN}"

# Fetch ticket details
TICKET_JSON=$(curl -sf -u "$AUTH" "${BASE_URL}/api/v2/tickets/${TICKET_ID}.json") || {
  echo "Error: Failed to fetch ticket #${TICKET_ID}" >&2
  echo "Check your credentials and that the ticket exists." >&2
  exit 1
}

# Fetch all comments with pagination
ALL_COMMENTS="[]"
COMMENTS_URL="${BASE_URL}/api/v2/tickets/${TICKET_ID}/comments.json?page[size]=100"

while [ -n "$COMMENTS_URL" ]; do
  COMMENTS_PAGE=$(curl -sf -u "$AUTH" "$COMMENTS_URL") || {
    echo "Error: Failed to fetch comments for ticket #${TICKET_ID}" >&2
    exit 1
  }

  PAGE_COMMENTS=$(echo "$COMMENTS_PAGE" | jq '.comments')
  ALL_COMMENTS=$(echo "$ALL_COMMENTS" "$PAGE_COMMENTS" | jq -s '.[0] + .[1]')

  # Check for next page
  HAS_MORE=$(echo "$COMMENTS_PAGE" | jq -r '.meta.has_more // false')
  if [ "$HAS_MORE" = "true" ]; then
    COMMENTS_URL=$(echo "$COMMENTS_PAGE" | jq -r '.links.next // empty')
  else
    COMMENTS_URL=""
  fi
done

if [ "$RAW_JSON" = true ]; then
  jq -n \
    --argjson ticket "$TICKET_JSON" \
    --argjson comments "$ALL_COMMENTS" \
    '{ticket: $ticket.ticket, comments: $comments}'
  exit 0
fi

# Format and display
echo "$TICKET_JSON" | jq -r '
  .ticket |
  "╔══════════════════════════════════════════════════════════════╗",
  "║ Ticket #\(.id): \(.subject)",
  "╚══════════════════════════════════════════════════════════════╝",
  "",
  "  Status:    \(.status)      Priority: \(.priority // "none")",
  "  Requester: \(.requester_id)    Assignee: \(.assignee_id // "unassigned")",
  "  Created:   \(.created_at)      Updated:  \(.updated_at)",
  "  Tags:      \((.tags // []) | join(", "))",
  ""
'

SHOW_INTERNAL_VAR="$SHOW_INTERNAL"
export SHOW_INTERNAL_VAR

echo "$ALL_COMMENTS" | jq -r --arg show_internal "$SHOW_INTERNAL" '
  .[] |
  if ($show_internal == "false") and (.public == false) then empty
  else
    "───────────────────────────────────────────────────────────────",
    (if .public then "  [Public]" else "  [Internal Note]" end) +
      "  Author: \(.author_id)  |  \(.created_at)",
    "",
    (.plain_body // .body // "(no content)") |
      split("\n") | map("  " + .) | join("\n"),
    ""
  end
'

echo "═══════════════════════════════════════════════════════════════"
