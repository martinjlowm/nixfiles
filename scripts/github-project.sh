# Usage: github-project <tech-spec.md> <source-project-url>
#   github-project specs/tech-spec.md https://github.com/orgs/FactbirdHQ/projects/77
set -e

# ESTIMATION_TEMPLATE is set by the Nix derivation
SPEC_FILE="${1:-}"
SOURCE_PROJECT_URL="${2:-}"

if [ -z "$SPEC_FILE" ] || [ -z "$SOURCE_PROJECT_URL" ]; then
  echo "Usage: github-project <tech-spec.md> <source-project-url>"
  echo ""
  echo "Arguments:"
  echo "  tech-spec.md        Path to the technical breakdown / spec file"
  echo "  source-project-url  GitHub project URL to copy view-setup from"
  echo ""
  echo "Translates a technical breakdown into a GitHub project copied from the"
  echo "source project (preserving view-setup for sprint check-ins) and creates"
  echo "tasks across sprints according to the estimation baseline."
  echo ""
  echo "Examples:"
  echo "  github-project specs/tech-spec.md https://github.com/orgs/FactbirdHQ/projects/77"
  exit 1
fi

# Validate spec file exists
if [ ! -f "$SPEC_FILE" ]; then
  echo "Error: Spec file not found: $SPEC_FILE"
  exit 1
fi

# Validate it looks like a GitHub project URL
if [[ "$SOURCE_PROJECT_URL" != *"github.com"*"/projects/"* ]]; then
  echo "Error: Expected a GitHub project URL, got: $SOURCE_PROJECT_URL"
  echo "Expected format: https://github.com/orgs/<org>/projects/<number>"
  exit 1
fi

# Resolve spec file to absolute path
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"

# Determine the source code directory
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

# Agent prompt is managed by home-manager at ~/.claude/agents/github-project.md
AGENT_PATH="$HOME/.claude/agents/github-project.md"

if [ ! -f "$AGENT_PATH" ]; then
  echo "Error: GitHub project agent prompt not found at $AGENT_PATH"
  exit 1
fi

# Build the prompt from the agent template
AGENT_PROMPT=$(sed \
  -e "s|__SPEC_FILE__|$SPEC_FILE|g" \
  -e "s|__SOURCE_PROJECT_URL__|$SOURCE_PROJECT_URL|g" \
  -e "s|__ESTIMATION_TEMPLATE__|$ESTIMATION_TEMPLATE|g" \
  -e "s|__SOURCE_DIR__|$SOURCE_DIR|g" \
  "$AGENT_PATH")

echo "GitHub Project Creator"
echo "Spec file:       $SPEC_FILE"
echo "Source project:  $SOURCE_PROJECT_URL"
echo "Estimation:      $ESTIMATION_TEMPLATE"
echo "Source code:     $SOURCE_DIR"
echo ""

SESSION_ID=$(uuidgen)
echo "Session: $SESSION_ID"

echo "$AGENT_PROMPT" | claude \
  --session-id "$SESSION_ID" \
  -p \
  --allowedTools "Read,Glob,Grep,Bash,Agent,Write" \
  2>&1 | tee /dev/stderr
