#!/bin/bash
# ============================================================
# MH-OAN Docker Compose — Start Script (WSL Compatible)
# ============================================================
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ──────────────────────────────────────────────
# Functions
# ──────────────────────────────────────────────

print_banner() {
    echo -e "${CYAN}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  🚀 MH-OAN Complete System (Docker Compose)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${NC}"
}

check_prerequisites() {
    echo -e "${BLUE}🔍 Checking prerequisites...${NC}"

    # Check Docker
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}❌ Docker is not installed.${NC}"
        echo "  Install: https://docs.docker.com/engine/install/"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Docker $(docker --version | awk '{print $3}' | tr -d ',')"

    # Check Docker Compose (v2 plugin)
    if docker compose version &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Docker Compose $(docker compose version --short 2>/dev/null || echo 'v2')"
    elif command -v docker-compose &>/dev/null; then
        echo -e "  ${YELLOW}⚠ Using legacy docker-compose. Consider upgrading to Docker Compose V2.${NC}"
        COMPOSE_CMD="docker-compose"
    else
        echo -e "${RED}❌ Docker Compose is not installed.${NC}"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info &>/dev/null; then
        echo -e "${RED}❌ Docker daemon is not running. Please start Docker first.${NC}"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} Docker daemon is running"

    # Check .env file
    if [ ! -f ".env" ]; then
        echo -e "${RED}❌ .env file not found!${NC}"
        echo "  Copy .env.example to .env and fill in your API keys:"
        echo "    cp .env.example .env"
        exit 1
    fi
    echo -e "  ${GREEN}✓${NC} .env file found"

    # Warn if API keys are still placeholders
    if grep -q "YOUR_GEMINI_API_KEY_HERE" .env 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ GEMINI_API_KEY is still a placeholder — OAN LLM will fail!${NC}"
    fi
    if grep -q "YOUR_MAPBOX_TOKEN_HERE" .env 2>/dev/null; then
        echo -e "  ${YELLOW}⚠ MAPBOX_API_TOKEN is still a placeholder — maps will not work!${NC}"
    fi

    echo ""
}

cmd_up() {
    local SKIP_NOMINATIM="${1:-false}"
    print_banner
    check_prerequisites

    echo -e "${BLUE}📥 Pulling latest images...${NC}"
    if [ "$SKIP_NOMINATIM" = "true" ]; then
        docker compose pull --ignore-pull-failures $(docker compose config --services | grep -v nominatim) 2>/dev/null || true
    else
        docker compose pull --ignore-pull-failures 2>/dev/null || true
    fi
    echo ""

    echo -e "${BLUE}🚀 Starting services...${NC}"
    if [ "$SKIP_NOMINATIM" = "true" ]; then
        echo -e "  ${YELLOW}⚠ Skipping Nominatim (use --with-nominatim to include)${NC}"
        docker compose up -d --remove-orphans $(docker compose config --services | grep -v nominatim)
    else
        echo -e "  ${CYAN}ℹ Including Nominatim — first run will take 10-30 minutes for OSM data import${NC}"
        docker compose up -d --remove-orphans
    fi
    echo ""

    # Wait for critical services
    echo -e "${BLUE}⏳ Waiting for services to be healthy...${NC}"
    local TIMEOUT=120
    local WAITED=0

    # Wait for Redis
    printf "  Redis: "
    while ! docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q PONG; do
        sleep 2
        WAITED=$((WAITED + 2))
        if [ $WAITED -ge $TIMEOUT ]; then
            echo -e "${RED}TIMEOUT${NC}"
            break
        fi
        printf "."
    done
    echo -e " ${GREEN}✓${NC}"

    # Wait for Postgres
    WAITED=0
    printf "  Postgres: "
    while ! docker compose exec -T telemetry-postgres pg_isready -U postgres 2>/dev/null | grep -q "accepting"; do
        sleep 2
        WAITED=$((WAITED + 2))
        if [ $WAITED -ge $TIMEOUT ]; then
            echo -e "${RED}TIMEOUT${NC}"
            break
        fi
        printf "."
    done
    echo -e " ${GREEN}✓${NC}"

    # Wait for OAN LLM
    WAITED=0
    printf "  OAN LLM API: "
    while ! curl -sf http://localhost:8000/docs >/dev/null 2>&1; do
        sleep 3
        WAITED=$((WAITED + 3))
        if [ $WAITED -ge $TIMEOUT ]; then
            echo -e "${YELLOW}TIMEOUT (may still be starting)${NC}"
            break
        fi
        printf "."
    done
    if [ $WAITED -lt $TIMEOUT ]; then
        echo -e " ${GREEN}✓${NC}"
    fi

    # Wait for OAN UI
    WAITED=0
    printf "  OAN UI: "
    while ! curl -sf http://localhost:8081 >/dev/null 2>&1; do
        sleep 2
        WAITED=$((WAITED + 2))
        if [ $WAITED -ge 60 ]; then
            echo -e "${YELLOW}TIMEOUT${NC}"
            break
        fi
        printf "."
    done
    if [ $WAITED -lt 60 ]; then
        echo -e " ${GREEN}✓${NC}"
    fi
    echo ""

    # Print status
    cmd_status
}

cmd_down() {
    echo -e "${BLUE}⏹️  Stopping all MH-OAN services...${NC}"
    docker compose down
    echo -e "${GREEN}✓ All services stopped${NC}"
}

cmd_restart() {
    echo -e "${BLUE}🔄 Restarting all services...${NC}"
    docker compose restart
    echo ""
    cmd_status
}

cmd_logs() {
    local SERVICE="${1:-}"
    if [ -n "$SERVICE" ]; then
        docker compose logs -f "$SERVICE"
    else
        docker compose logs -f
    fi
}

cmd_status() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🐳 Container Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    echo ""

    # Check auth mode
    BYPASS_AUTH=$(grep -E "^BYPASS_AUTH=" .env 2>/dev/null | cut -d'=' -f2)

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🌐 Access Points${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    if [ "$BYPASS_AUTH" = "true" ]; then
        echo -e "  🔓 ${YELLOW}Auth Bypassed (dev mode)${NC}"
    else
        echo -e "  🔐 ${GREEN}Authentication Required${NC}"
    fi
    echo ""
    echo -e "  📱 OAN Frontend UI:       ${GREEN}http://localhost:8081${NC}"
    echo -e "  📱 OAN Frontend:           ${GREEN}http://localhost:8081${NC}"
    echo -e "  🔧 API Docs (OAN LLM):     ${GREEN}http://localhost:8000/docs${NC}"
    echo -e "  🔷 Beckn Mock BAP:         ${GREEN}http://localhost:8001${NC}"
    echo -e "  📊 Telemetry Dashboard:    ${GREEN}http://localhost:8881${NC}"
    echo -e "  🔑 Keycloak Admin:         ${GREEN}http://localhost:8082${NC}"
    echo -e "  🗺️  Nominatim Geocoding:   ${GREEN}http://localhost:8080${NC}"
    echo -e "  🛢️  PostgreSQL:             ${GREEN}localhost:5441${NC}"
    echo -e "  📦 Redis:                  ${GREEN}localhost:6379${NC}"
    echo ""

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  🔑 Default Credentials${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Keycloak Admin:   ${BOLD}admin${NC} / ${BOLD}admin${NC}"
    echo -e "  Dashboard (admin): ${BOLD}kelvin${NC} / ${BOLD}1234${NC}"
    echo -e "  Dashboard (viewer): ${BOLD}viewer${NC} / ${BOLD}viewer123${NC}"
    echo -e "  PostgreSQL:       ${BOLD}postgres${NC} / ${BOLD}1234${NC}"
    echo ""
}

cmd_clean() {
    echo -e "${RED}⚠️  This will stop all containers AND delete all volumes (data)!${NC}"
    read -p "Are you sure? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        docker compose down -v --remove-orphans
        echo -e "${GREEN}✓ All containers and volumes removed${NC}"
    else
        echo "Cancelled."
    fi
}

cmd_help() {
    echo -e "${BOLD}Usage:${NC} ./start-mh-oan.sh [COMMAND]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  up                Start all services (default, skips Nominatim)"
    echo "  up --with-nominatim  Start all services including Nominatim"
    echo "  down              Stop all services"
    echo "  restart           Restart all services"
    echo "  status            Show service status and access URLs"
    echo "  logs [service]    Tail logs (all or specific service)"
    echo "  clean             Stop and remove all containers + volumes"
    echo "  help              Show this help message"
    echo ""
    echo -e "${BOLD}Services:${NC}"
    echo "  redis, telemetry-postgres, nominatim, beckn-mock,"
    echo "  oan-llm, oan-ui, telemetry-dashboard-service,"
    echo "  telemetry-processor, keycloak, telemetry-dashboard-ui"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./start-mh-oan.sh                    # Start without Nominatim"
    echo "  ./start-mh-oan.sh up --with-nominatim # Start with Nominatim"
    echo "  ./start-mh-oan.sh logs oan-llm       # Tail OAN LLM logs"
    echo "  ./start-mh-oan.sh down               # Stop everything"
    echo "  BYPASS_AUTH=false ./start-mh-oan.sh   # Start with auth enabled"
    echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
COMMAND="${1:-up}"

case "$COMMAND" in
    up)
        if [ "${2:-}" = "--with-nominatim" ]; then
            cmd_up "false"
        else
            cmd_up "true"
        fi
        ;;
    down)
        cmd_down
        ;;
    restart)
        cmd_restart
        ;;
    status)
        cmd_status
        ;;
    logs)
        cmd_logs "${2:-}"
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
