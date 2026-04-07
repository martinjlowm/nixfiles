# Usage: tech-spec <notion-url> [output-file]
#   tech-spec https://www.notion.so/...           - fill out a tech spec from a Notion product spec
#   tech-spec https://www.notion.so/... spec.md   - same, writing to a specific output file
set -e

# TECH_SPEC_TEMPLATE and TECH_SPEC_MCP_CONFIG are set by the Nix derivation
NOTION_URL="${1:-}"

if [ -z "$NOTION_URL" ]; then
  echo "Usage: tech-spec <notion-url> [output-file]"
  echo ""
  echo "Arguments:"
  echo "  notion-url   URL to the Notion product specification"
  echo "  output-file  Output path for the tech spec (default: specs/tech-spec-<timestamp>.md)"
  echo ""
  echo "Spawns Claude with Notion access to read the product spec and fill out"
  echo "a technical specification grounded in the current codebase."
  exit 1
fi

# Validate it looks like a Notion URL
if [[ "$NOTION_URL" != *"notion"* ]]; then
  echo "Error: Expected a Notion URL, got: $NOTION_URL"
  exit 1
fi

# Determine the source code directory
# If we're in a bare git repo, find the worktree that tracks master
SOURCE_DIR="$(pwd)"
if [ "$(git rev-parse --is-bare-repository 2>/dev/null)" = "true" ]; then
  echo "Bare git repository detected — looking for master worktree..."
  MASTER_WORKTREE=$(git worktree list | grep '\[master\]' | awk '{print $1}')
  if [ -z "$MASTER_WORKTREE" ]; then
    MASTER_WORKTREE=$(git worktree list | grep '\[main\]' | awk '{print $1}')
  fi
  if [ -z "$MASTER_WORKTREE" ]; then
    echo "Error: No worktree found for master or main branch."
    echo "Available worktrees:"
    git worktree list
    exit 1
  fi
  SOURCE_DIR="$MASTER_WORKTREE"
  echo "Using worktree: $SOURCE_DIR"
fi

REPO="$(cd "$SOURCE_DIR" && git rev-parse --show-toplevel)"

# Determine output path
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_PATH="${2:-$REPO/specs/tech-spec-$TIMESTAMP.md}"
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
mkdir -p "$OUTPUT_DIR"

# Agent prompt is managed by home-manager at ~/.claude/agents/tech-spec.md
AGENT_PATH="$HOME/.claude/agents/tech-spec.md"

if [ ! -f "$AGENT_PATH" ]; then
  echo "Error: Tech spec agent prompt not found at $AGENT_PATH"
  exit 1
fi

# Build the prompt from the agent template
AGENT_PROMPT=$(sed \
  -e "s|__NOTION_URL__|$NOTION_URL|g" \
  -e "s|__TEMPLATE_PATH__|$TECH_SPEC_TEMPLATE|g" \
  -e "s|__SOURCE_DIR__|$SOURCE_DIR|g" \
  -e "s|__OUTPUT_PATH__|$OUTPUT_PATH|g" \
  "$AGENT_PATH")

echo "Tech Spec Generator"
echo "Notion URL:  $NOTION_URL"
echo "Source code: $SOURCE_DIR"
echo "Output:      $OUTPUT_PATH"
echo ""

SESSION_ID=$(uuidgen)
echo "Session: $SESSION_ID"

echo "$AGENT_PROMPT" | claude \
  --session-id "$SESSION_ID" \
  --mcp-config "$TECH_SPEC_MCP_CONFIG" \
  -p \
  --allowedTools "mcp__notion*,Read,Glob,Grep,Write,Agent,Bash" \
  2>&1 | tee /dev/stderr

if [ -f "$OUTPUT_PATH" ]; then
  echo ""
  echo "Tech spec written to: $OUTPUT_PATH"
else
  echo ""
  echo "Warning: Output file was not created at $OUTPUT_PATH"
  echo "Check the Claude session output above for errors."
fi
