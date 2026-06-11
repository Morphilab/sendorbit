# tests/setup.bash — Loads libraries from the project root with isolated log dirs
# Usage: source "$(dirname "$BATS_TEST_FILENAME")/setup.bash"

SENDORBIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Create isolated temp dir before sourcing any lib so their := fallbacks
# pick up our values instead of using PROJECT_ROOT/logs
export LOGS_DIR
LOGS_DIR="$(mktemp -d)"
export LOG_FILE="$LOGS_DIR/sendorbit.log"
export SECURITY_LOG="$LOGS_DIR/security.log"

source "$SENDORBIT_ROOT/lib/utils.sh"
source "$SENDORBIT_ROOT/lib/validation.sh"
source "$SENDORBIT_ROOT/lib/logging.sh"
source "$SENDORBIT_ROOT/lib/security.sh"
