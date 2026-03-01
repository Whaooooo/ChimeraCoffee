#!/usr/bin/env bash
set -euo pipefail

# dev-start.sh - Start the Chimera Coffee development environment
# 
# This script:
#   - Checks prerequisites
#   - Shows current git branch info (no auto-checkout)
#   - Starts/verifies MongoDB
#   - Builds backend if needed
#   - Initializes database with seed data
#   - Starts backend server
#   - Starts frontend dev server (optional)
#
# Usage:
#   ./dev-start.sh              # Start backend + frontend
#   ./dev-start.sh --backend-only   # Start only backend
#   ./dev-start.sh --frontend-only  # Start only frontend
#   ./dev-start.sh --skip-build     # Skip Maven build (use existing JAR)
#   ./dev-start.sh --skip-db-init   # Skip database initialization
#   ./dev-start.sh --reset-db       # Reset MongoDB data directory

# Auto-detect directory structure
# Supports both:
#   1. Scripts in project_root/test/ (legacy)
#   2. Scripts in project_root/ChimeraCoffee/dev-scripts/ (new)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

if [[ -f "${SCRIPT_DIR}/../pom.xml" ]]; then
    # We're in ChimeraCoffee/dev-scripts/ (new structure)
    BACKEND_DIR="${SCRIPT_DIR}/.."
    BASE_DIR="${BACKEND_DIR}/.."
    FRONTEND_DIR="${BASE_DIR}/chimera-management"
else
    # We're in project_root/test/ (legacy structure)
    BASE_DIR="${SCRIPT_DIR}/.."
    BACKEND_DIR="${BASE_DIR}/ChimeraCoffee"
    FRONTEND_DIR="${BASE_DIR}/chimera-management"
fi

LOG_DIR="${BACKEND_DIR}/log"
mkdir -p "$LOG_DIR"

# PID files
BACKEND_PID_FILE="${LOG_DIR}/backend.pid"
MONGO_PID_FILE="${LOG_DIR}/mongo.pid"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

# Default config
: "${SERVER_PORT:=8088}"
: "${FRONTEND_PORT:=5173}"

: "${MONGO_HOST:=127.0.0.1}"
: "${MONGO_PORT:=27017}"
: "${MONGO_DATABASE:=chimera_local}"
: "${MONGO_USERNAME:=chimera}"
: "${MONGO_PASSWORD:=chimera}"
: "${MONGO_AUTHENTICATION_DATABASE:=admin}"

: "${ADMIN_USERNAME:=admin}"
: "${ADMIN_PASSWORD:=admin123}"

# Java configuration - prefer Java 17 for compatibility
setup_java() {
    if [[ -z "${JAVA_HOME:-}" ]]; then
        # Try to find Java 17
        if [[ -x "/usr/lib/jvm/java-17-openjdk-amd64/bin/java" ]]; then
            export JAVA_HOME="/usr/lib/jvm/java-17-openjdk-amd64"
            export PATH="$JAVA_HOME/bin:$PATH"
            log_info "Using Java 17 from $JAVA_HOME"
        elif [[ -x "/usr/lib/jvm/java-17/bin/java" ]]; then
            export JAVA_HOME="/usr/lib/jvm/java-17"
            export PATH="$JAVA_HOME/bin:$PATH"
            log_info "Using Java 17 from $JAVA_HOME"
        fi
    fi
    
    local java_version
    java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2 | cut -d'.' -f1)
    if [[ "$java_version" != "17" ]]; then
        log_warn "Java version is $java_version, but Java 17 is recommended for this project"
    fi
}

# Flags
BACKEND_ONLY=0
FRONTEND_ONLY=0
SKIP_BUILD=0
SKIP_DB_INIT=0
RESET_DB=0

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --backend-only)
                BACKEND_ONLY=1
                shift
                ;;
            --frontend-only)
                FRONTEND_ONLY=1
                shift
                ;;
            --skip-build)
                SKIP_BUILD=1
                shift
                ;;
            --skip-db-init)
                SKIP_DB_INIT=1
                shift
                ;;
            --reset-db)
                RESET_DB=1
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --backend-only    Start only the backend"
                echo "  --frontend-only   Start only the frontend"
                echo "  --skip-build      Skip Maven build (use existing JAR)"
                echo "  --skip-db-init    Skip database initialization"
                echo "  --reset-db        Reset MongoDB data directory before starting"
                echo "  --help, -h        Show this help"
                echo ""
                echo "Environment variables:"
                echo "  SERVER_PORT       Backend port (default: 8088)"
                echo "  FRONTEND_PORT     Frontend port (default: 5173)"
                echo "  MONGO_*           MongoDB configuration"
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

need_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Missing required command: $1"
        exit 1
    fi
}

print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║    Chimera Coffee - Dev Environment Startup      ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
}

show_repo_info() {
    log_info "Repository Status:"
    echo ""
    
    for repo_dir in "$BACKEND_DIR" "$FRONTEND_DIR"; do
        local repo_name
        repo_name=$(basename "$repo_dir")
        local branch
        branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        local commit
        commit=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
        local dirty=""
        if git -C "$repo_dir" status --porcelain 2>/dev/null | grep -q .; then
            dirty=" ${YELLOW}(dirty)${NC}"
        fi
        echo "  $repo_name: ${GREEN}$branch${NC} @ $commit$dirty"
    done
    echo ""
}

# MongoDB functions
ping_mongo() {
    local uri="mongodb://${MONGO_USERNAME}:${MONGO_PASSWORD}@${MONGO_HOST}:${MONGO_PORT}/${MONGO_DATABASE}?authSource=${MONGO_AUTHENTICATION_DATABASE}"
    mongosh "$uri" --quiet --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1
}

port_in_use() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -q ":${port}$"
    elif command -v lsof >/dev/null 2>&1; then
        lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    else
        return 1
    fi
}

start_mongo() {
    log_info "Checking MongoDB..."
    
    if ping_mongo; then
        log_success "MongoDB is already running and accessible"
        return 0
    fi
    
    if port_in_use "$MONGO_PORT"; then
        log_error "Port $MONGO_PORT is in use, but MongoDB credentials don't work"
        log_error "You may need to:"
        log_error "  1. Check your MongoDB credentials, or"
        log_error "  2. Stop the existing MongoDB instance, or"
        log_error "  3. Adjust MONGO_* environment variables"
        exit 1
    fi
    
    log_info "Starting local MongoDB..."
    
    MONGO_DATA_DIR="${BACKEND_DIR}/.local-mongo"
    
    if [[ "$RESET_DB" == "1" && -d "$MONGO_DATA_DIR" ]]; then
        log_warn "Removing existing MongoDB data directory..."
        rm -rf "$MONGO_DATA_DIR"
    fi
    
    mkdir -p "$MONGO_DATA_DIR"
    
    # If fresh data dir, create admin user first
    if [[ ! -f "${MONGO_DATA_DIR}/WiredTiger" ]]; then
        log_info "Initializing MongoDB data directory..."
        
        mongod \
            --dbpath "$MONGO_DATA_DIR" \
            --bind_ip "$MONGO_HOST" \
            --port "$MONGO_PORT" \
            --fork \
            --logpath "${LOG_DIR}/mongo.log" \
            --pidfilepath "${LOG_DIR}/mongo.pid"
        
        # Wait for MongoDB to be ready
        sleep 2
        
        log_info "Creating initial admin user..."
        mongosh "mongodb://${MONGO_HOST}:${MONGO_PORT}/admin" --quiet <<EOF
const adminDb = db.getSiblingDB('admin');
try {
    adminDb.createUser({
        user: '${MONGO_USERNAME}',
        pwd: '${MONGO_PASSWORD}',
        roles: [{ role: 'readWrite', db: '${MONGO_DATABASE}' }]
    });
    print('User created successfully');
} catch (e) {
    if (e.codeName === "UserAlreadyExists" || e.code === 51003) {
        print('User already exists');
    } else {
        throw e;
    }
}
EOF
        
        log_info "Restarting MongoDB with authentication..."
        mongod --dbpath "$MONGO_DATA_DIR" --shutdown 2>/dev/null || true
        sleep 1
    fi
    
    # Start MongoDB with auth
    mongod \
        --dbpath "$MONGO_DATA_DIR" \
        --bind_ip "$MONGO_HOST" \
        --port "$MONGO_PORT" \
        --auth \
        --fork \
        --logpath "${LOG_DIR}/mongo.log" \
        --pidfilepath "$MONGO_PID_FILE"
    
    # Wait and verify
    local attempts=0
    while ! ping_mongo && [[ $attempts -lt 10 ]]; do
        sleep 1
        ((attempts++))
    done
    
    if ping_mongo; then
        log_success "MongoDB started successfully"
    else
        log_error "MongoDB failed to start"
        exit 1
    fi
}

# Backend functions
setup_wechat_keys() {
    log_info "Setting up WeChat dummy keys..."
    
    WECHAT_KEY_DIR="${BACKEND_DIR}/.local-wechat-keys"
    WECHAT_PRIVATE_CANDIDATE="${SCRIPT_DIR}/wechat-mch-private.pem"
    WECHAT_PUBLIC_CANDIDATE="${SCRIPT_DIR}/wechatpay-pub.pem"
    
    if [[ -f "$WECHAT_PRIVATE_CANDIDATE" && -f "$WECHAT_PUBLIC_CANDIDATE" ]]; then
        export WECHAT_PRIVATE_KEY_PATH="$WECHAT_PRIVATE_CANDIDATE"
        export WECHATPAY_PUBLIC_KEY_PATH="$WECHAT_PUBLIC_CANDIDATE"
        log_success "Using existing WeChat keys from test/"
    else
        mkdir -p "$WECHAT_KEY_DIR"
        if [[ ! -f "${WECHAT_KEY_DIR}/merchant-private.pem" ]]; then
            if ! command -v openssl >/dev/null 2>&1; then
                log_error "openssl not found; cannot generate dummy WeChat keys"
                exit 1
            fi
            openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 \
                -out "${WECHAT_KEY_DIR}/merchant-private.pem" >/dev/null 2>&1
            openssl rsa -in "${WECHAT_KEY_DIR}/merchant-private.pem" -pubout \
                -out "${WECHAT_KEY_DIR}/wechatpay-public.pem" >/dev/null 2>&1
        fi
        export WECHAT_PRIVATE_KEY_PATH="${WECHAT_KEY_DIR}/merchant-private.pem"
        export WECHATPAY_PUBLIC_KEY_PATH="${WECHAT_KEY_DIR}/wechatpay-public.pem"
        log_success "Generated new dummy WeChat keys"
    fi
}

build_backend() {
    if [[ "$SKIP_BUILD" == "1" ]]; then
        log_info "Skipping backend build (--skip-build)"
        return 0
    fi
    
    log_info "Building backend with Maven..."
    
    # Use local Maven repo
    export MAVEN_USER_HOME="${BACKEND_DIR}/.m2"
    export MAVEN_LOCAL_REPO="${MAVEN_USER_HOME}/repository"
    mkdir -p "$MAVEN_USER_HOME"
    
    (cd "$BACKEND_DIR" && mvn -Dmaven.repo.local="$MAVEN_LOCAL_REPO" -DskipTests clean package)
    
    log_success "Backend build completed"
}

init_database() {
    if [[ "$SKIP_DB_INIT" == "1" ]]; then
        log_info "Skipping database initialization (--skip-db-init)"
        return 0
    fi
    
    log_info "Initializing database..."
    
    # Export all needed env vars for the init script
    export MONGO_HOST MONGO_PORT MONGO_DATABASE MONGO_USERNAME MONGO_PASSWORD MONGO_AUTHENTICATION_DATABASE
    export ADMIN_USERNAME ADMIN_PASSWORD
    export MAVEN_USER_HOME="${BACKEND_DIR}/.m2"
    export MAVEN_LOCAL_REPO="${MAVEN_USER_HOME}/repository"
    
    # Source and run the init script
    # shellcheck source=./dev-init-db.sh
    source "${SCRIPT_DIR}/dev-init-db.sh"
}

start_backend() {
    log_info "Starting backend..."
    
    local jar_path
    jar_path=$(ls -1 "${BACKEND_DIR}/target/"*.jar 2>/dev/null | grep -v '\.original$' | head -n 1 || true)
    
    if [[ -z "$jar_path" ]]; then
        log_error "Backend JAR not found. Build may have failed."
        exit 1
    fi
    
    # Set up environment
    export SERVER_PORT
    export MONGO_HOST MONGO_PORT MONGO_DATABASE MONGO_USERNAME MONGO_PASSWORD MONGO_AUTHENTICATION_DATABASE
    
    LOCAL_STATIC_DIR="${BACKEND_DIR}/.local-static"
    mkdir -p "$LOCAL_STATIC_DIR"
    export FILE_UPLOAD_DIR="$LOCAL_STATIC_DIR"
    export SPRING_WEB_RESOURCES_STATIC_LOCATIONS="file:${LOCAL_STATIC_DIR}/"
    export APP_URL="http://localhost:${SERVER_PORT}"
    
    # WeChat config
    setup_wechat_keys
    export WECHAT_APPID="${WECHAT_APPID:-wx_local}"
    export WECHAT_SECRET="${WECHAT_SECRET:-local_secret}"
    export WECHAT_MCHID="${WECHAT_MCHID:-1900000109}"
    export WECHAT_MERCHANT_SERIAL_NUMBER="${WECHAT_MERCHANT_SERIAL_NUMBER:-local_serial}"
    export WECHAT_API_V3_KEY="${WECHAT_API_V3_KEY:-0123456789ABCDEF0123456789ABCDEF}"
    export WECHATPAY_PUBLIC_KEY_ID="${WECHATPAY_PUBLIC_KEY_ID:-local_wechatpay_key}"
    export WECHATPAY_NOTIFICATION_USE_COMBINED="${WECHATPAY_NOTIFICATION_USE_COMBINED:-false}"
    export WECHAT_PREPAY_NOTIFY_URL="http://localhost:${SERVER_PORT}/wechat/prepay_notify"
    export WECHAT_REFUND_NOTIFY_URL="http://localhost:${SERVER_PORT}/wechat/refund_notify"
    export WECHAT_STATE="${WECHAT_STATE:-local}"
    
    # Start backend
    local backend_log
    backend_log="${LOG_DIR}/backend_$(date +%Y%m%d_%H%M%S).log"
    
    java -Dfile.encoding=utf-8 -jar "$jar_path" >"$backend_log" 2>&1 &
    local backend_pid=$!
    echo "$backend_pid" > "$BACKEND_PID_FILE"
    
    # Wait for backend to be ready
    log_info "Waiting for backend to start..."
    local attempts=0
    while [[ $attempts -lt 30 ]]; do
        if curl -s "http://localhost:${SERVER_PORT}/actuator/health" >/dev/null 2>&1 || \
           curl -s "http://localhost:${SERVER_PORT}" >/dev/null 2>&1; then
            break
        fi
        if ! kill -0 "$backend_pid" 2>/dev/null; then
            log_error "Backend process died. Check log: $backend_log"
            exit 1
        fi
        sleep 1
        ((attempts++))
        echo -n "."
    done
    echo ""
    
    if kill -0 "$backend_pid" 2>/dev/null; then
        log_success "Backend started (PID: $backend_pid)"
        log_info "Backend log: $backend_log"
    else
        log_error "Backend failed to start. Check log: $backend_log"
        exit 1
    fi
}

# Frontend functions
setup_frontend_env() {
    log_info "Configuring frontend environment..."
    
    # Create .env.local for development (gitignored, takes precedence)
    local env_file="${FRONTEND_DIR}/.env.local"
    
    cat > "$env_file" << EOF
# Auto-generated by dev-start.sh
# This file is gitignored and overrides .env.development
VITE_API_BASE_URL=http://localhost:${SERVER_PORT}
VITE_HIPRINT_HOST=http://localhost:17521
EOF
    
    log_success "Frontend environment configured (.env.local)"
    log_info "API URL: http://localhost:${SERVER_PORT}"
}

start_frontend() {
    log_info "Setting up frontend..."
    
    if [[ ! -d "${FRONTEND_DIR}/node_modules" ]]; then
        log_info "Installing frontend dependencies (this may take a while)..."
        (cd "$FRONTEND_DIR" && npm install)
    fi
    
    setup_frontend_env
    
    log_info "Starting frontend dev server..."
    log_info "Once started, access the frontend at: http://localhost:${FRONTEND_PORT}"
    echo ""
    log_info "Press Ctrl+C to stop"
    echo ""
    
    cd "$FRONTEND_DIR"
    npm run dev -- --host --port "$FRONTEND_PORT"
}

# Cleanup
cleanup_on_exit() {
    if [[ -f "$BACKEND_PID_FILE" ]]; then
        local pid
        pid=$(cat "$BACKEND_PID_FILE" 2>/dev/null || true)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping backend (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$BACKEND_PID_FILE"
    fi
    
    # Clean up frontend .env.local
    local env_file="${FRONTEND_DIR}/.env.local"
    if [[ -f "$env_file" ]]; then
        rm -f "$env_file"
        log_info "Cleaned up frontend environment"
    fi
    
    echo ""
    log_info "Development environment stopped"
}

# Main
main() {
    parse_args "$@"
    
    # Check for conflicting flags
    if [[ "$BACKEND_ONLY" == "1" && "$FRONTEND_ONLY" == "1" ]]; then
        log_error "Cannot use both --backend-only and --frontend-only"
        exit 1
    fi
    
    print_banner
    
    # Check prerequisites
    need_cmd git
    need_cmd java
    need_cmd mongosh
    need_cmd mongod
    
    if [[ "$FRONTEND_ONLY" != "1" ]]; then
        need_cmd mvn
    fi
    
    if [[ "$BACKEND_ONLY" != "1" ]]; then
        need_cmd node
        need_cmd npm
    fi
    
    # Setup Java version
    setup_java
    
    show_repo_info
    
    if [[ "$FRONTEND_ONLY" != "1" ]]; then
        start_mongo
        build_backend
        init_database
        start_backend
    fi
    
    if [[ "$BACKEND_ONLY" != "1" ]]; then
        if [[ "$FRONTEND_ONLY" == "1" ]]; then
            # Check if backend is running
            if ! curl -s "http://localhost:${SERVER_PORT}" >/dev/null 2>&1; then
                log_warn "Backend doesn't seem to be running on port ${SERVER_PORT}"
                log_warn "Make sure to start it first with: $0 --backend-only"
                echo ""
                # Auto-continue if not running interactively (tty)
                if [[ -t 0 ]]; then
                    read -p "Continue anyway? [y/N] " -n 1 -r
                    echo ""
                    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                        exit 1
                    fi
                else
                    log_info "Non-interactive mode, continuing anyway..."
                fi
            fi
        fi
        
        # Set up trap to clean up backend when frontend exits (if we started it)
        if [[ "$FRONTEND_ONLY" != "1" ]]; then
            trap cleanup_on_exit EXIT INT TERM
        fi
        
        start_frontend
    else
        # Backend only mode - keep running
        echo ""
        log_success "Backend is running on http://localhost:${SERVER_PORT}"
        log_info "API Documentation: http://localhost:${SERVER_PORT}/swagger-ui.html"
        log_info "Admin login: ${ADMIN_USERNAME} / ${ADMIN_PASSWORD}"
        echo ""
        log_info "Press Ctrl+C to stop"
        
        # Wait for interrupt
        trap 'echo ""; log_info "Stopping..."; cleanup_on_exit; exit 0' INT TERM
        while true; do
            sleep 1
        done
    fi
}

main "$@"
