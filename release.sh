#!/usr/bin/env bash
set -euo pipefail

# ccvitals — Release Script
# https://github.com/educlopez/ccvitals
#
# Usage:
#   ./release.sh 1.2.0          Create release v1.2.0 (commit + tag, no push)
#   ./release.sh 1.2.0 --push   Create release v1.2.0 and push to origin

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC} $1"; }
error() { echo -e "${RED}[error]${NC} $1"; exit 1; }

# --- Parse arguments ---
VERSION=""
PUSH=false

for arg in "$@"; do
    case "$arg" in
        --push) PUSH=true ;;
        --help|-h)
            echo "Usage: ./release.sh <version> [--push]"
            echo ""
            echo "  <version>   Semantic version (e.g., 1.2.0)"
            echo "  --push      Push commit and tag to origin after creating them"
            echo ""
            echo "Examples:"
            echo "  ./release.sh 1.2.0"
            echo "  ./release.sh 1.2.0 --push"
            exit 0
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$arg"
            else
                error "Unexpected argument: $arg"
            fi
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    error "Usage: ./release.sh <version> [--push]\n  Example: ./release.sh 1.2.0"
fi

# --- Validate semver format ---
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    error "Invalid version format: '$VERSION'. Expected semver (e.g., 1.2.0)"
fi

info "Preparing release v${VERSION}..."

# --- Ensure we're in the repo root ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "Not inside a git repository"
fi

# --- Check for clean working directory ---
if [ -n "$(git status --porcelain)" ]; then
    error "Working directory is not clean. Commit or stash changes first."
fi

# --- Check that tag does not already exist ---
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    error "Tag v${VERSION} already exists"
fi

# --- Detect sed variant (BSD vs GNU) ---
# BSD sed (macOS) requires -i '' while GNU sed uses -i without argument
SED_INPLACE=""
if sed --version >/dev/null 2>&1; then
    # GNU sed
    SED_INPLACE="sed -i"
else
    # BSD sed (macOS)
    SED_INPLACE="sed -i ''"
fi

# --- Bump STATUSLINE_VERSION in all three scripts ---
SCRIPTS="statusline.sh install.sh uninstall.sh"
for script in $SCRIPTS; do
    if [ ! -f "$script" ]; then
        error "Script not found: $script"
    fi

    # Check that the version line exists
    if ! grep -q '^STATUSLINE_VERSION=' "$script"; then
        error "STATUSLINE_VERSION not found in $script"
    fi

    # Replace version using eval to handle BSD/GNU sed difference
    eval "$SED_INPLACE 's/^STATUSLINE_VERSION=.*/STATUSLINE_VERSION=\"${VERSION}\"/' \"$script\""
    ok "Updated version in $script"
done

# --- Verify all scripts have the same version ---
for script in $SCRIPTS; do
    found=$(grep '^STATUSLINE_VERSION=' "$script" | head -1 | sed 's/STATUSLINE_VERSION="//' | sed 's/"//')
    if [ "$found" != "$VERSION" ]; then
        error "Version mismatch in $script: expected '$VERSION', found '$found'"
    fi
done
ok "All scripts have version $VERSION"

# --- Validate CHANGELOG.md has an entry for this version ---
if [ ! -f "CHANGELOG.md" ]; then
    error "CHANGELOG.md not found"
fi

if ! grep -q "\\[${VERSION}\\]" "CHANGELOG.md"; then
    error "CHANGELOG.md does not contain an entry for version ${VERSION}.\n  Add a ## [${VERSION}] section before releasing."
fi
ok "CHANGELOG.md has entry for v${VERSION}"

# --- Commit the version bump ---
git add statusline.sh install.sh uninstall.sh
info "Committing version bump..."
git commit -m "release: v${VERSION}

Bump STATUSLINE_VERSION to ${VERSION} in all scripts."

ok "Created commit for v${VERSION}"

# --- Create annotated git tag ---
git tag -a "v${VERSION}" -m "Release v${VERSION}"
ok "Created tag v${VERSION}"

# --- Optional push + publish ---
if [ "$PUSH" = true ]; then
    info "Pushing to origin..."
    git push origin HEAD
    git push origin "v${VERSION}"
    ok "Pushed commit and tag to origin"

    # --- GitHub Release (notes from CHANGELOG) ---
    if command -v gh >/dev/null 2>&1; then
        info "Creating GitHub Release..."
        NOTES_FILE="$(mktemp)"
        awk "/^## \\[${VERSION}\\]/{f=1;next} /^## \\[/{f=0} f" CHANGELOG.md > "$NOTES_FILE"
        if [ -s "$NOTES_FILE" ] && gh release create "v${VERSION}" --title "v${VERSION}" --notes-file "$NOTES_FILE"; then
            ok "GitHub Release v${VERSION} created"
        else
            warn "GitHub Release creation failed — create it manually:"
            echo "  gh release create v${VERSION} --title v${VERSION} --notes-file <notes>"
        fi
        rm -f "$NOTES_FILE"

        # --- Homebrew tap formula update ---
        TAP_REPO="educlopez/homebrew-tap"
        FORMULA_PATH="Formula/ccvitals.rb"
        info "Updating Homebrew tap (${TAP_REPO})..."
        TARBALL_URL="https://github.com/educlopez/ccvitals/archive/refs/tags/v${VERSION}.tar.gz"
        # -f makes curl fail on HTTP errors (404 body would otherwise hash to a
        # valid 64-char sha and poison the formula)
        TARBALL_TMP="$(mktemp)"
        if curl -fsSL "$TARBALL_URL" -o "$TARBALL_TMP"; then
            TARBALL_SHA="$(shasum -a 256 "$TARBALL_TMP" | awk '{print $1}')"
        else
            TARBALL_SHA=""
        fi
        rm -f "$TARBALL_TMP"
        if [ -n "$TARBALL_SHA" ] && [ "${#TARBALL_SHA}" -eq 64 ]; then
            FORMULA_TMP="$(mktemp)"
            FORMULA_SHA="$(gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" --jq '.sha')"
            gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" --jq '.content' | base64 -d > "$FORMULA_TMP"
            eval "$SED_INPLACE 's|tags/v[0-9][0-9.]*\\.tar\\.gz|tags/v${VERSION}.tar.gz|; s|sha256 \".*\"|sha256 \"${TARBALL_SHA}\"|' \"$FORMULA_TMP\""
            if gh api -X PUT "repos/${TAP_REPO}/contents/${FORMULA_PATH}" \
                -f message="ccvitals ${VERSION}" \
                -f content="$(base64 -i "$FORMULA_TMP")" \
                -f sha="$FORMULA_SHA" >/dev/null; then
                ok "Homebrew tap updated to v${VERSION}"
            else
                warn "Tap update failed — update ${TAP_REPO}/${FORMULA_PATH} manually (url + sha256 ${TARBALL_SHA})"
            fi
            rm -f "$FORMULA_TMP"
        else
            warn "Could not compute tarball sha256 — update tap manually:"
            echo "  curl -sL ${TARBALL_URL} | shasum -a 256"
        fi
    else
        warn "gh CLI not found — skipping GitHub Release and Homebrew tap update"
    fi
else
    echo ""
    info "Release v${VERSION} created locally. To push:"
    echo "  git push origin HEAD && git push origin v${VERSION}"
    echo "  (with --push this also creates the GitHub Release and updates the Homebrew tap)"
fi

echo ""
echo -e "${GREEN}Release v${VERSION} complete!${NC}"
