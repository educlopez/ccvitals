#!/usr/bin/env bash
set -euo pipefail

# ccvitals — Test Runner
# Runs the bats test suite with automatic helper setup.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/test"
LIB_DIR="$TEST_DIR/lib"

# Colors (respects NO_COLOR)
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    CYAN=''
    NC=''
fi

info()  { echo -e "${CYAN}[info]${NC} $1"; }
ok()    { echo -e "${GREEN}[ok]${NC} $1"; }
fail()  { echo -e "${RED}[error]${NC} $1"; }

# Check for bats
if ! command -v bats >/dev/null 2>&1; then
    fail "bats-core is not installed."
    echo ""
    echo "  Install options:"
    echo ""
    echo "    # macOS (Homebrew)"
    echo "    brew install bats-core"
    echo ""
    echo "    # npm"
    echo "    npm install -g bats"
    echo ""
    echo "    # Git clone"
    echo "    git clone https://github.com/bats-core/bats-core.git /tmp/bats-core"
    echo "    sudo /tmp/bats-core/install.sh /usr/local"
    echo ""
    exit 1
fi

ok "bats found: $(bats --version)"

# Install bats-support and bats-assert if not present
if [ ! -d "$LIB_DIR/bats-support" ] || [ ! -d "$LIB_DIR/bats-assert" ]; then
    info "Installing bats-support and bats-assert into test/lib/..."
    mkdir -p "$LIB_DIR"

    if [ ! -d "$LIB_DIR/bats-support" ]; then
        git clone --depth 1 https://github.com/bats-core/bats-support.git "$LIB_DIR/bats-support" 2>/dev/null
    fi

    if [ ! -d "$LIB_DIR/bats-assert" ]; then
        git clone --depth 1 https://github.com/bats-core/bats-assert.git "$LIB_DIR/bats-assert" 2>/dev/null
    fi

    ok "bats helpers installed"
fi

# Run the tests
info "Running bats tests..."
echo ""
bats "$TEST_DIR"/*.bats "$@"
