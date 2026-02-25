#!/bin/bash
# ============================================================
# MH-OAN Docker Compose — Stop Script
# ============================================================
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

print_banner() {
    echo -e "${CYAN}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🛑 Stopping MH-OAN System"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${NC}"
}

cmd_stop() {
    print_banner
    echo -e "${BLUE}⏹️  Stopping all services gracefully...${NC}"
    docker compose stop
    echo -e "${GREEN}✓ All services stopped successfully.${NC}"
    echo "  (Data volumes and container states are preserved)"
    echo "  To start again, run: ./start-mh-oan.sh"
}

cmd_down() {
    print_banner
    echo -e "${BLUE}🗑️  Removing all containers and networks...${NC}"
    docker compose down
    echo -e "${GREEN}✓ All containers and networks removed.${NC}"
    echo "  (Data volumes are preserved)"
    echo "  To start again, run: ./start-mh-oan.sh"
}

cmd_clean() {
    print_banner
    echo -e "${RED}⚠️  WARNING: This will destroy all containers AND all data volumes!${NC}"
    echo -e "  You will lose all PostgreSQL data, Redis caches, and Nominatim imports."
    read -p "Are you absolutely sure you want to wipe everything? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}🗑️  Wiping everything...${NC}"
        docker compose down -v --remove-orphans
        echo -e "${GREEN}✓ All containers, networks, and volumes destroyed.${NC}"
    else
        echo "Cancelled clean operation."
    fi
}

cmd_help() {
    echo -e "${BOLD}Usage:${NC} ./stop-mh-oan.sh [COMMAND]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  stop       (Default) Stop containers gracefully but keep them around."
    echo "             Fastest way to pause the system."
    echo "  down       Stop and remove containers & networks. Keeps data volumes."
    echo "             Use this if you changed docker-compose.yml."
    echo "  clean      Stop, remove containers, and DESTROY ALL DATA VOLUMES."
    echo "             Use this to completely reset the system."
    echo "  help       Show this help message."
    echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
COMMAND="${1:-stop}"

case "$COMMAND" in
    stop)
        cmd_stop
        ;;
    down)
        cmd_down
        ;;
    clean)
        cmd_clean
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        echo -e "${RED}Unknown command: $COMMAND${NC}"
        cmd_help
        exit 1
        ;;
esac
