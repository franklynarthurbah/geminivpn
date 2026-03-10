#!/bin/bash
# =============================================================================
# GeminiVPN Deployment Script
# Main deployment orchestrator for the entire platform
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# =============================================================================
# Helper Functions
# =============================================================================

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                                                              ║"
    echo "║     ██████╗ ███████╗███╗   ███╗██╗███╗   ██╗██╗   ██╗██████╗ ███╗   ██╗    ║"
    echo "║    ██╔════╝ ██╔════╝████╗ ████║██║████╗  ██║██║   ██║██╔══██╗████╗  ██║    ║"
    echo "║    ██║  ███╗█████╗  ██╔████╔██║██║██╔██╗ ██║██║   ██║██████╔╝██╔██╗ ██║    ║"
    echo "║    ██║   ██║██╔══╝  ██║╚██╔╝██║██║██║╚██╗██║╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║    ║"
    echo "║    ╚██████╔╝███████╗██║ ╚═╝ ██║██║██║ ╚████║ ╚████╔╝ ██║     ██║ ╚████║    ║"
    echo "║     ╚═════╝ ╚══════╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝     ╚═╝  ╚═══╝    ║"
    echo "║                                                              ║"
    echo "║              Secure VPN Platform Deployment                  ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_step() {
    echo -e "${CYAN}→ $1${NC}"
}

# =============================================================================
# Pre-deployment Checks
# =============================================================================

check_prerequisites() {
    print_step "Checking prerequisites..."
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        print_error "Docker Compose is not installed"
        echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        exit 1
    fi
    
    print_success "Prerequisites check passed"
}

# =============================================================================
# Environment Setup
# =============================================================================

setup_environment() {
    print_step "Setting up environment..."
    
    cd "$PROJECT_DIR"
    
    # Create .env file if it doesn't exist
    if [[ ! -f .env ]]; then
        if [[ -f .env.example ]]; then
            cp .env.example .env
            print_warning "Created .env file from .env.example"
            print_warning "Please edit .env with your actual values before continuing"
            exit 1
        else
            print_error ".env file not found"
            exit 1
        fi
    fi
    
    # Load environment variables
    set -a
    source .env
    set +a
    
    print_success "Environment loaded"
}

# =============================================================================
# Database Setup
# =============================================================================

setup_database() {
    print_step "Setting up database..."
    
    cd "$PROJECT_DIR/docker"
    
    # Start only database services
    docker-compose up -d postgres redis
    
    # Wait for database to be ready
    print_info "Waiting for database to be ready..."
    sleep 10
    
    # Check if database is healthy
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if docker-compose exec -T postgres pg_isready -U "${DB_USER:-geminivpn}" &> /dev/null; then
            print_success "Database is ready"
            break
        fi
        retries=$((retries + 1))
        sleep 2
    done
    
    if [[ $retries -eq 30 ]]; then
        print_error "Database failed to start"
        exit 1
    fi
    
    # Run migrations
    print_info "Running database migrations..."
    cd "$PROJECT_DIR/backend"
    
    # Install dependencies if needed
    if [[ ! -d node_modules ]]; then
        npm install
    fi
    
    # Generate Prisma client
    npx prisma generate
    
    # Run migrations
    npx prisma migrate deploy
    
    # Seed database
    print_info "Seeding database..."
    npx ts-node prisma/seed.ts
    
    print_success "Database setup completed"
}

# =============================================================================
# Build Application
# =============================================================================

build_application() {
    print_step "Building application..."
    
    cd "$PROJECT_DIR/docker"
    
    # Build all services
    docker-compose build
    
    print_success "Application built successfully"
}

# =============================================================================
# Deploy Application
# =============================================================================

deploy_application() {
    print_step "Deploying application..."
    
    cd "$PROJECT_DIR/docker"
    
    # Stop existing containers
    docker-compose down
    
    # Start all services
    docker-compose up -d
    
    # Wait for backend to be healthy
    print_info "Waiting for backend to be ready..."
    sleep 15
    
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if curl -sf http://localhost:5000/health &> /dev/null; then
            print_success "Backend is healthy"
            break
        fi
        retries=$((retries + 1))
        sleep 2
    done
    
    if [[ $retries -eq 30 ]]; then
        print_error "Backend failed to start"
        print_info "Check logs with: docker-compose logs backend"
        exit 1
    fi
    
    print_success "Application deployed successfully"
}

# =============================================================================
# Health Check
# =============================================================================

health_check() {
    print_step "Running health checks..."
    
    local base_url="${FRONTEND_URL:-http://localhost:5000}"
    
    # Check API health
    if curl -sf "${base_url}/health" &> /dev/null; then
        print_success "API is responding"
    else
        print_error "API health check failed"
        return 1
    fi
    
    # Check database connection
    cd "$PROJECT_DIR/docker"
    if docker-compose exec -T backend curl -sf http://localhost:5000/health &> /dev/null; then
        print_success "Database connection verified"
    else
        print_warning "Could not verify database connection"
    fi
    
    print_success "Health checks passed"
}

# =============================================================================
# Display Info
# =============================================================================

display_info() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}              GeminiVPN Deployment Complete!${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Access Information:${NC}"
    echo "  API Endpoint: ${FRONTEND_URL:-http://localhost:5000}"
    echo "  Health Check: ${FRONTEND_URL:-http://localhost:5000}/health"
    echo ""
    echo -e "${BLUE}Test User Credentials:${NC}"
    echo "  Email: alibasma"
    echo "  Password: alibabaat2026"
    echo "  Status: Full Access (Test Account)"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  View logs:        docker-compose -f docker/docker-compose.yml logs -f"
    echo "  Restart backend:  docker-compose -f docker/docker-compose.yml restart backend"
    echo "  Database shell:   docker-compose -f docker/docker-compose.yml exec postgres psql -U ${DB_USER:-geminivpn}"
    echo "  Update:           ./scripts/deploy.sh"
    echo ""
    echo -e "${BLUE}Support:${NC}"
    echo "  WhatsApp: ${WHATSAPP_SUPPORT_NUMBER:-+1234567890}"
    echo "  Email: ${SUPPORT_EMAIL:-support@geminivpn.com}"
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
}

# =============================================================================
# Rollback
# =============================================================================

rollback() {
    print_warning "Deployment failed, rolling back..."
    
    cd "$PROJECT_DIR/docker"
    docker-compose down
    
    print_info "Rollback completed"
}

# =============================================================================
# Main
# =============================================================================

main() {
    print_banner
    
    # Parse arguments
    local skip_build=false
    local skip_db=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                skip_build=true
                shift
                ;;
            --skip-db)
                skip_db=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --skip-build    Skip building Docker images"
                echo "  --skip-db       Skip database setup"
                echo "  --help          Show this help message"
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    # Run deployment steps
    check_prerequisites
    setup_environment
    
    if [[ "$skip_db" != true ]]; then
        setup_database
    fi
    
    if [[ "$skip_build" != true ]]; then
        build_application
    fi
    
    deploy_application
    health_check
    display_info
}

# Handle errors
trap rollback ERR

# Run main function
main "$@"
