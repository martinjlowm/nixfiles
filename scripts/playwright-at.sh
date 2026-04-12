fetch_browsers_json() {
  local tag="$1"
  # Newer versions: packages/playwright-core/browsers.json
  # Older versions (e.g. v1.9.1): browsers.json at repo root
  curl -sf "https://raw.githubusercontent.com/microsoft/playwright/${tag}/packages/playwright-core/browsers.json" \
    || curl -sf "https://raw.githubusercontent.com/microsoft/playwright/${tag}/browsers.json" \
    || true
}

chromium_major_from_release() {
  local body="$1"
  # Release notes consistently list "Chromium <version>" across all Playwright eras.
  # This is the authoritative source for which Chromium ships with a given Playwright
  # version — browsers.json only gained a "browserVersion" field at v1.22, and older
  # versions' "revision" field is a Chromium commit position that doesn't trivially
  # map back to a marketing version.
  echo "$body" | grep -oE 'Chromium [0-9]+' | head -1 | cut -d' ' -f2
}

CHROME_VERSION="${1:-}"
if [ -z "$CHROME_VERSION" ]; then
  echo "Usage: playwright-at <chrome-major-version>"
  echo "Example: playwright-at 98"
  exit 1
fi

CACHE_DIR="$HOME/.playwright-browsers/.cache"
mkdir -p "$CACHE_DIR"
CACHE_FILE="$CACHE_DIR/chrome-${CHROME_VERSION}.txt"

if [ -f "$CACHE_FILE" ]; then
  PW_VERSION=$(cat "$CACHE_FILE")
  echo "Cached: Chrome $CHROME_VERSION → Playwright v$PW_VERSION"
else
  echo "Searching for Playwright version shipping Chrome $CHROME_VERSION..."

  # GitHub releases API returns 30 per page by default (max 100). Paginate through
  # releases and extract the Chromium version from each release body. This is far
  # faster than fetching browsers.json per-tag, and works across all Playwright eras.
  PW_VERSION=""
  PAGE=1
  while [ -z "$PW_VERSION" ]; do
    RELEASES=$(curl -sf "https://api.github.com/repos/microsoft/playwright/releases?per_page=100&page=${PAGE}")

    # Stop if we got an empty page
    COUNT=$(echo "$RELEASES" | jq 'length')
    if [ "$COUNT" = "0" ] || [ "$COUNT" = "null" ]; then
      break
    fi

    # Find the latest release whose Chromium major version matches
    MATCH=$(echo "$RELEASES" | jq -r --arg target "$CHROME_VERSION" '
      [.[] |
        select(.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) |
        {
          tag: .tag_name,
          chrome_major: (
            .body
            | capture("Chromium (?<v>[0-9]+)")
            | .v
          )
        }
      ]
      | map(select(.chrome_major == $target))
      | first
      | .tag // empty
    ')

    if [ -n "$MATCH" ]; then
      PW_VERSION="${MATCH#v}"
      echo "$PW_VERSION" > "$CACHE_FILE"
      echo "Found: Chrome $CHROME_VERSION → Playwright v$PW_VERSION"
    else
      PAGE=$((PAGE + 1))
    fi
  done

  if [ -z "$PW_VERSION" ]; then
    echo "Could not find a Playwright version shipping Chrome $CHROME_VERSION"
    exit 1
  fi
fi

BROWSERS_PATH="$HOME/.playwright-browsers/$PW_VERSION"
mkdir -p "$BROWSERS_PATH"

BROWSERS_JSON=$(fetch_browsers_json "v${PW_VERSION}")

CHROMIUM_REVISION=$(echo "$BROWSERS_JSON" | \
  jq -r '.browsers[] | select(.name == "chromium") | .revision')

echo "Installing Chromium revision $CHROMIUM_REVISION to $BROWSERS_PATH..."

PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_PATH" \
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=0 \
  npx "playwright@$PW_VERSION" install chromium

echo ""
echo "Done. To use this browser in your tests:"
echo "  PLAYWRIGHT_BROWSERS_PATH=$BROWSERS_PATH npx playwright@$PW_VERSION test"
echo ""
echo "Or in your playwright config:"
echo "  executablePath: '$BROWSERS_PATH/chromium-$CHROMIUM_REVISION/chrome-linux/chrome'"
