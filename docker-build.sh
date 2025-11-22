#!/bin/bash
# docker-build.sh - Helper script for building with Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

usage() {
    cat << EOF
Usage: $0 [command] [options]

Commands:
    build-image     Build the Docker image
    shell           Start an interactive shell in the container
    build           Build tools (pass arguments to build.sh)
    clean           Clean build artifacts
    help            Show this help message

Examples:
    $0 build-image
    $0 shell
    $0 build --arch arm glib2
    $0 build --arch arm64 --all
    $0 clean

EOF
}

build_image() {
    log "Building Docker image..."
    docker-compose build
    log "Docker image built successfully"
}

start_shell() {
    log "Starting interactive shell..."
    docker-compose run --rm nethunter-build /bin/bash
}

run_build() {
    log "Running build command: ./build.sh $*"
    docker-compose run --rm nethunter-build ./build.sh "$@"
}

clean_artifacts() {
    log "Cleaning build artifacts..."
    docker-compose run --rm nethunter-build ./build.sh clean
    log "Build artifacts cleaned"
}

# Main script
case "${1:-help}" in
    build-image)
        build_image
        ;;
    shell)
        start_shell
        ;;
    build)
        shift
        run_build "$@"
        ;;
    clean)
        clean_artifacts
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
