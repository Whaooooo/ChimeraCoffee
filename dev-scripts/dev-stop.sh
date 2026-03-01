#!/usr/bin/env bash
set -euo pipefail

# dev-stop.sh - Stop the Chimera Coffee development environment
#
# This script stops:
#   - Backend Java process (via PID file)
#   - Local MongoDB instance (via PID file)
#
# Usage:
#   ./dev-stop.sh           # Stop backend and MongoDB
#   ./dev-stop.sh --soft    # Stop only backend, keep MongoDB running
#   ./dev-stop.sh --clean   # Stop everything and remove MongoDB data

# Auto-detect directory structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

if [[ -f "${SCRIPT_DIR}/../pom.xml" ]]; then
    # We're in ChimeraCoffee/dev-scripts/ (new structure)
    BACKEND_DIR="${SCRIPT_DIR}/.."
else
    # We're in project_root/test/ (legacy structure)
    BACKEND_DIR="${SCRIPT_DIR}/../ChimeraCoffee"
fi

LOG_DIR="${BACKEND_DIR}/log"
MONGO_DATA_DIR="${BACKEND_DIR}/.local-mongo"

BACKEND_PID_FILE="${LOG_DIR}/backend.pid"
MONGO_PID_FILE="${LOG_DIR}/mongo.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[STOP]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[STOP]${NC} $*"; }
log_error() { echo -e "${RED}[STOP]${NC} $*"; }
log_success() { echo -e "${GREEN}[STOP]${NC} $*"; }

SOFT_MODE=0
CLEAN_MODE=0

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --soft)
                SOFT_MODE=1
                shift
                ;;
            --clean)
                CLEAN_MODE=1
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --soft     Stop only backend, keep MongoDB running"
                echo "  --clean    Stop everything and remove MongoDB data directory"
                echo "  --help, -h Show this help"
                echo ""
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

stop_by_pid_file() {
    local label="$1"
    local pid_file="$2"
    local signal="${3:-TERM}"
    
    if [[ ! -f "$pid_file" ]]; then
        log_warn "$label: no PID file found ($pid_file)"
        return 1
    fi
    
    local pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    
    if [[ -z "$pid" ]]; then
        log_warn "$label: PID file is empty"
        rm -f "$pid_file"
        return 1
    fi
    
    if ! kill -0 "$pid" 2>/dev/null; then
        log_warn "$label: process not running (PID: $pid)"
        rm -f "$pid_file"
        return 1
    fi
    
    log_info "$label: stopping (PID: $pid)..."
    
    if kill -"$signal" "$pid" 2>/dev/null; then
        # Wait for process to actually stop
        local attempts=0
        while kill -0 "$pid" 2>/dev/null && [[ $attempts -lt 10 ]]; do
            sleep 0.5
            ((attempts++))
        done
        
        if kill -0 "$pid" 2>/dev/null; then
            log_warn "$label: still running, forcing kill..."
            kill -9 "$pid" 2>/dev/null || true
        fi
        
        log_success "$label: stopped"
    else
        log_error "$label: failed to stop"
    fi
    
    rm -f "$pid_file"
}

stop_backend() {
    stop_by_pid_file "Backend" "$BACKEND_PID_FILE" "TERM"
}

stop_mongo() {
    if [[ "$SOFT_MODE" == "1" ]]; then
        log_info "Soft mode: keeping MongoDB running"
        return 0
    fi
    
    stop_by_pid_file "MongoDB" "$MONGO_PID_FILE" "TERM"
    
    if [[ "$CLEAN_MODE" == "1" ]]; then
        if [[ -d "$MONGO_DATA_DIR" ]]; then
            log_info "Removing MongoDB data directory..."
            rm -rf "$MONGO_DATA_DIR"
            log_success "MongoDB data removed"
        fi
    fi
}

cleanup_frontend_env() {
    # Auto-detect frontend location
    if [[ -f "${SCRIPT_DIR}/../pom.xml" ]]; then
        # We're in ChimeraCoffee/dev-scripts/
        local env_file="${SCRIPT_DIR}/../../chimera-management/.env.local"
    else
        # We're in project_root/test/
        local env_file="${SCRIPT_DIR}/../chimera-management/.env.local"
    fi
    
    if [[ -f "$env_file" ]]; then
        log_info "Cleaning up frontend environment..."
        rm -f "$env_file"
        log_success "Frontend environment cleaned"
    fi
    
    # Also clean up legacy backup file if it exists
    local customize_file
    if [[ -f "${SCRIPT_DIR}/../pom.xml" ]]; then
        customize_file="${SCRIPT_DIR}/../../chimera-management/src/client/customize.ts"
    else
        customize_file="${SCRIPT_DIR}/../chimera-management/src/client/customize.ts"
    fi
    local backup_file="${customize_file}.dev.bak"
    if [[ -f "$backup_file" ]]; then
        rm -f "$backup_file"
    fi
}

print_summary() {
    echo ""
    log_success "Cleanup complete"
    echo ""
    
    if [[ "$CLEAN_MODE" == "1" ]]; then
        log_info "MongoDB data directory has been removed"
        log_info "Next start will create fresh data"
    elif [[ "$SOFT_MODE" != "1" ]]; then
        log_info "MongoDB data is preserved at: $MONGO_DATA_DIR"
        log_info "To also remove data, use: $0 --clean"
    fi
    
    echo ""
    log_info "To restart: ./dev-start.sh"
}

main() {
    parse_args "$@"
    
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║    Chimera Coffee - Dev Environment Stop         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    stop_backend
    stop_mongo
    cleanup_frontend_env
    print_summary
}

main "$@"
