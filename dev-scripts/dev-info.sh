#!/usr/bin/env bash
set -euo pipefail

# dev-info.sh - Display development environment information
# Shows git branch/status for all three repos and checks prerequisites

# Auto-detect directory structure
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

if [[ -f "${SCRIPT_DIR}/../pom.xml" ]]; then
    # We're in ChimeraCoffee/dev-scripts/ (new structure)
    BACKEND_DIR="${SCRIPT_DIR}/.."
    BASE_DIR="${BACKEND_DIR}/.."
else
    # We're in project_root/test/ (legacy structure)
    BASE_DIR="${SCRIPT_DIR}/.."
    BACKEND_DIR="${BASE_DIR}/ChimeraCoffee"
fi

FRONTEND_DIR="${BASE_DIR}/chimera-management"
MINIAPP_DIR="${BASE_DIR}/chimeracoffeeweb-master"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }

print_separator() {
    echo "=================================================="
}

check_prerequisites() {
    print_separator
    log_info "Checking Prerequisites"
    print_separator
    
    local all_ok=true
    
    # Java
    if command -v java >/dev/null 2>&1; then
        local java_version
        java_version=$(java -version 2>&1 | head -n1 | cut -d'"' -f2)
        log_success "Java: $java_version"
    else
        log_error "Java: NOT FOUND (required: Java 17+)"
        all_ok=false
    fi
    
    # Maven
    if command -v mvn >/dev/null 2>&1; then
        local mvn_version
        mvn_version=$(mvn --version 2>/dev/null | head -n1 | cut -d' ' -f3)
        log_success "Maven: $mvn_version"
    else
        log_error "Maven: NOT FOUND"
        all_ok=false
    fi
    
    # MongoDB
    if command -v mongod >/dev/null 2>&1 && command -v mongosh >/dev/null 2>&1; then
        local mongo_version
        mongo_version=$(mongod --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        log_success "MongoDB: $mongo_version"
    else
        log_error "MongoDB: NOT FOUND (mongod and mongosh required)"
        all_ok=false
    fi
    
    # Node.js
    if command -v node >/dev/null 2>&1; then
        local node_version
        node_version=$(node -v)
        log_success "Node.js: $node_version"
    else
        log_error "Node.js: NOT FOUND"
        all_ok=false
    fi
    
    # npm
    if command -v npm >/dev/null 2>&1; then
        local npm_version
        npm_version=$(npm -v)
        log_success "npm: $npm_version"
    else
        log_error "npm: NOT FOUND"
        all_ok=false
    fi
    
    if $all_ok; then
        echo ""
        log_success "All prerequisites satisfied!"
    else
        echo ""
        log_error "Some prerequisites are missing. Please install them first."
        exit 1
    fi
}

git_repo_info() {
    local repo_dir="$1"
    local repo_name="$2"
    
    print_separator
    log_info "Repository: $repo_name"
    print_separator
    
    if [[ ! -d "$repo_dir/.git" ]]; then
        log_error "Not a git repository: $repo_dir"
        return 1
    fi
    
    local branch
    branch=$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    
    local commit
    commit=$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    
    local status
    if git -C "$repo_dir" status --porcelain 2>/dev/null | grep -q .; then
        status="${YELLOW}dirty (uncommitted changes)${NC}"
    else
        status="${GREEN}clean${NC}"
    fi
    
    echo "  Directory: $repo_dir"
    echo -e "  Branch:    ${GREEN}$branch${NC}"
    echo "  Commit:    $commit"
    echo -e "  Status:    $status"
    
    # Show last commit info
    local last_commit
    last_commit=$(git -C "$repo_dir" log -1 --format="%h - %s (%ar)" 2>/dev/null || echo "N/A")
    echo "  Last:      $last_commit"
}

check_mongo_status() {
    print_separator
    log_info "MongoDB Status"
    print_separator
    
    local mongo_host="${MONGO_HOST:-127.0.0.1}"
    local mongo_port="${MONGO_PORT:-27017}"
    
    if mongosh "mongodb://${mongo_host}:${mongo_port}/admin" --quiet --eval "db.runCommand({ ping: 1 })" >/dev/null 2>&1; then
        log_success "MongoDB is running on ${mongo_host}:${mongo_port}"
        local mongo_version
        mongo_version=$(mongosh "mongodb://${mongo_host}:${mongo_port}/admin" --quiet --eval "db.version()" 2>/dev/null || echo "unknown")
        echo "  Version: $mongo_version"
    else
        log_warn "MongoDB is NOT running on ${mongo_host}:${mongo_port}"
        echo "  Run './dev-start.sh' to start it automatically, or start your own MongoDB instance"
    fi
}

check_backend_build() {
    print_separator
    log_info "Backend Build Status"
    print_separator
    
    local jar_files
    jar_files=$(ls -1 "${BACKEND_DIR}/target/"*.jar 2>/dev/null | grep -v '\.original$' || true)
    
    if [[ -n "$jar_files" ]]; then
        log_success "Backend JAR found:"
        echo "$jar_files" | while read -r jar; do
            local jar_size
            jar_size=$(du -h "$jar" 2>/dev/null | cut -f1)
            echo "  - $(basename "$jar") ($jar_size)"
        done
    else
        log_warn "Backend JAR not found. Need to build."
        echo "  Run './dev-start.sh' to build automatically"
    fi
}

check_frontend_deps() {
    print_separator
    log_info "Frontend Dependencies Status"
    print_separator
    
    if [[ -d "${FRONTEND_DIR}/node_modules" ]]; then
        local pkg_count
        pkg_count=$(ls -1 "${FRONTEND_DIR}/node_modules" 2>/dev/null | wc -l)
        log_success "Frontend dependencies installed ($pkg_count packages)"
    else
        log_warn "Frontend node_modules not found. Need to run 'npm install'."
    fi
}

main() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║    Chimera Coffee - Dev Environment Info         ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    echo ""
    
    git_repo_info "$BACKEND_DIR" "Backend (ChimeraCoffee)"
    echo ""
    
    git_repo_info "$FRONTEND_DIR" "Frontend (chimera-management)"
    echo ""
    
    git_repo_info "$MINIAPP_DIR" "Miniapp (chimeracoffeeweb-master)"
    echo ""
    
    check_mongo_status
    echo ""
    
    check_backend_build
    echo ""
    
    check_frontend_deps
    echo ""
    
    print_separator
    log_info "Quick Start Commands"
    print_separator
    echo ""
    echo "  Start everything:     ./dev-start.sh"
    echo "  Stop everything:      ./dev-stop.sh"
    echo "  View this info:       ./dev-info.sh"
    echo ""
    echo "  Backend only:         ./dev-start.sh --backend-only"
    echo "  Frontend only:        ./dev-start.sh --frontend-only"
    echo ""
    echo "  Access URLs (when running):"
    echo "    Backend API:    http://localhost:8088"
    echo "    Frontend:       http://localhost:5173"
    echo "    API Docs:       http://localhost:8088/swagger-ui.html"
    echo ""
}

main "$@"
