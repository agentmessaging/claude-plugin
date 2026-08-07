#!/bin/bash
# =============================================================================
# AMP Plugin Test Runner
# =============================================================================
#
# Usage:
#   ./run_tests.sh              # Run all tests
#   ./run_tests.sh unit         # Run unit tests only
#   ./run_tests.sh integration  # Run integration tests only
#   ./run_tests.sh <file>       # Run a specific test file
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure bats is installed
if [ ! -d "node_modules/.bin" ] || [ ! -x "node_modules/.bin/bats" ]; then
    echo "Installing test dependencies..."
    npm install
fi

BATS="node_modules/.bin/bats"
BATS_OPTS="--formatter tap"

case "${1:-all}" in
    unit)
        echo "Running unit tests..."
        $BATS $BATS_OPTS tests/unit/
        ;;
    integration)
        echo "Running integration tests..."
        $BATS $BATS_OPTS tests/integration/
        ;;
    all)
        echo "Running all tests..."
        $BATS $BATS_OPTS tests/unit/ tests/integration/
        ;;
    *)
        # Run specific file
        if [ -f "$1" ]; then
            echo "Running $1..."
            $BATS $BATS_OPTS "$1"
        else
            echo "Error: File not found: $1"
            echo ""
            echo "Usage: ./run_tests.sh [unit|integration|all|<file>]"
            exit 1
        fi
        ;;
esac
