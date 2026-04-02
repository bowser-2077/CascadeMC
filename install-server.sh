#!/bin/bash

# QwarkTracker Server Auto-Installation Script
# Supports Linux, macOS, and Windows (via WSL)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_INSTALL_DIR="/opt/qwarktracker"
DEFAULT_SERVICE_USER="root"
DEFAULT_SERVER_PORT="8000"
DEFAULT_WEB_PORT="3000"
DEFAULT_DB_TYPE="postgresql"
DEFAULT_DB_HOST="localhost"
DEFAULT_DB_PORT="5432"
DEFAULT_DB_NAME="qwarktracker"
DEFAULT_DB_USER="qwarktracker"
DEFAULT_DB_PASSWORD="qwarktracker123"
DEFAULT_REDIS_HOST="localhost"
DEFAULT_REDIS_PORT="6379"
DEFAULT_SERVER_PACKAGE="https://raw.githubusercontent.com/bowser-2077/CascadeMC/refs/heads/main/server.zip"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to download server package from GitHub
download_server_package() {
    local install_dir="$1"
    local package_url="$2"
    
    print_status "Downloading QwarkTracker server package..."
    
    # If package_url is a full URL, use it directly
    if [[ $package_url == http* ]]; then
        local download_url="$package_url"
        local filename=$(basename "$package_url")
    else
        # Otherwise, treat it as relative to server
        local download_url="${base_url}/${package_url}"
        local filename="$package_url"
    fi
    
    # Try to download the server package
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 30 -L -f "$download_url" -o "${install_dir}/${filename}"; then
            print_success "Server package downloaded from: $download_url"
            
            # Extract the package
            print_status "Extracting server package..."
            cd "$install_dir"
            
            if command -v unzip &> /dev/null; then
                unzip -q "${filename}" -d .
                rm "${filename}"
                print_success "Server package extracted"
                return 0
            else
                print_error "unzip not available, cannot extract package"
                return 1
            fi
        else
            print_warning "Failed to download server package from: $download_url"
            return 1
        fi
    elif command -v wget &> /dev/null; then
        if wget --timeout=30 --tries=3 "$download_url" -O "${install_dir}/${filename}" 2>/dev/null; then
            print_success "Server package downloaded from: $download_url"
            
            # Extract the package
            print_status "Extracting server package..."
            cd "$install_dir"
            
            if command -v unzip &> /dev/null; then
                unzip -q "${filename}" -d .
                rm "${filename}"
                print_success "Server package extracted"
                return 0
            else
                print_error "unzip not available, cannot extract package"
                return 1
            fi
        else
            print_warning "Failed to download server package from: $download_url"
            return 1
        fi
    else
        print_warning "Neither curl nor wget available for download"
        return 1
    fi
}

# Function to check if server files exist locally
check_local_files() {
    print_status "Checking for local server files..."
    
    if [ -f "server/app/main.py" ] && [ -f "docker-compose.yml" ] && [ -f "start.sh" ]; then
        print_success "Local server files found"
        return 0
    else
        print_warning "Local server files not complete"
        return 1
    fi
}

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        echo "windows"
    else
        echo "unknown"
    fi
}

# Function to get docker compose command
get_docker_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

# Function to check system requirements
check_requirements() {
    local os_type="$1"
    
    print_status "Checking system requirements..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is required but not installed"
        print_status "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        print_error "Docker Compose is required but not installed"
        print_status "Please install Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    print_success "System requirements met"
}

# Function to install system dependencies
install_dependencies() {
    local os_type="$1"
    
    print_status "Installing system dependencies..."
    
    case "$os_type" in
        "linux")
            # Check if running as root
            if [ "$EUID" -ne 0 ]; then
                print_warning "This script requires root privileges for Docker operations."
                print_warning "Running with sudo..."
                sudo "$0" "$@"
                exit $?
            fi
            
            # Install git if not present
            if ! command -v git &> /dev/null; then
                print_status "Installing git..."
                apt-get update && apt-get install -y git
            fi
            ;;
        "macos")
            # Install git if not present
            if ! command -v git &> /dev/null; then
                print_status "Installing git..."
                xcode-select --install 2>/dev/null || true
            fi
            ;;
        "windows")
            print_warning "Please ensure Git for Windows is installed"
            ;;
        *)
            print_warning "Unknown OS, skipping dependency installation"
            ;;
    esac
    
    print_success "Dependencies installed"
}

# Function to create environment file
create_env_file() {
    local install_dir="$1"
    local db_type="$2"
    local db_host="$3"
    local db_port="$4"
    local db_name="$5"
    local db_user="$6"
    local db_password="$7"
    local redis_host="$8"
    local redis_port="$9"
    local server_port="${10}"
    local web_port="${11}"
    
    print_status "Creating environment configuration..."
    
    local env_file="$install_dir/.env"
    
    # Generate secret key
    local secret_key=$(openssl rand -hex 32 2>/dev/null || date +%s | sha256sum | base64 | head -c 32)
    
    cat > "$env_file" << EOF
# QwarkTracker Server Configuration
DATABASE_URL=${db_type}://${db_user}:${db_password}@${db_host}:${db_port}/${db_name}
SECRET_KEY=${secret_key}
REDIS_URL=redis://${redis_host}:${redis_port}

# API Configuration
API_HOST=0.0.0.0
API_PORT=${server_port}
API_RELOAD=false
API_WORKERS=4

# Web Configuration
WEB_HOST=0.0.0.0
WEB_PORT=${web_port}

# Security
CORS_ORIGINS=["http://localhost:${web_port}", "http://127.0.0.1:${web_port}", "http://localhost:3000"]
ALLOWED_HOSTS=["localhost", "127.0.0.1", "0.0.0.0"]

# Monitoring
MONITORING_INTERVAL=30
METRICS_RETENTION_DAYS=30
ALERT_CHECK_INTERVAL=60

# Email (optional)
SMTP_HOST=
SMTP_PORT=587
SMTP_USERNAME=
SMTP_PASSWORD=
SMTP_FROM_EMAIL=

# Celery
CELERY_BROKER_URL=redis://${redis_host}:${redis_port}/0
CELERY_RESULT_BACKEND=redis://${redis_host}:${redis_port}/0
EOF

    print_success "Environment file created at $env_file"
}

# Function to setup database
setup_database() {
    local install_dir="$1"
    local db_type="$2"
    
    print_status "Setting up database..."
    
    cd "$install_dir"
    
    local compose_cmd=$(get_docker_compose_cmd)
    
    if [ "$db_type" = "postgresql" ]; then
        print_status "Starting PostgreSQL container..."
        $compose_cmd up -d postgres
        
        print_status "Waiting for PostgreSQL to be ready..."
        sleep 10
        
        print_status "Running database migrations..."
        $compose_cmd run --rm api alembic upgrade head
        
        print_success "Database setup complete"
    elif [ "$db_type" = "sqlite" ]; then
        print_status "Using SQLite database (no setup required)"
    fi
}

# Function to start services
start_services() {
    local install_dir="$1"
    
    print_status "Starting QwarkTracker services..."
    
    cd "$install_dir"
    local compose_cmd=$(get_docker_compose_cmd)
    
    # Start all services
    $compose_cmd up -d
    
    print_status "Waiting for services to start..."
    sleep 15
    
    # Check if services are running
    if $compose_cmd ps | grep -q "Up"; then
        print_success "QwarkTracker services started successfully!"
        echo ""
        echo "Service Status:"
        $compose_cmd ps
        echo ""
        echo "Access URLs:"
        echo "  Web Interface: http://localhost:3000"
        echo "  API: http://localhost:8000"
        echo "  API Docs: http://localhost:8000/docs"
        echo ""
        echo "Default Login:"
        echo "  Username: admin"
        echo "  Password: admin123"
        echo ""
        echo "Management Commands:"
        echo "  View logs: $compose_cmd logs -f"
        echo "  Stop services: $compose_cmd down"
        echo "  Restart services: $compose_cmd restart"
    else
        print_error "Failed to start services"
        $compose_cmd logs
        exit 1
    fi
}

# Function to test installation
test_installation() {
    local server_port="$1"
    local web_port="$2"
    
    print_status "Testing installation..."
    
    # Wait a bit more for services to be fully ready
    sleep 10
    
    # Test API
    if curl -s -f "http://localhost:${server_port}/health" > /dev/null 2>&1; then
        print_success "API is responding"
    else
        print_warning "API not yet responding (may still be starting)"
    fi
    
    # Test Web
    if curl -s -f "http://localhost:${web_port}" > /dev/null 2>&1; then
        print_success "Web interface is responding"
    else
        print_warning "Web interface not yet responding (may still be starting)"
    fi
}

# Function to show usage
usage() {
    echo "QwarkTracker Server Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --dir DIR          Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --server-port PORT     API server port (default: $DEFAULT_SERVER_PORT)"
    echo "  --web-port PORT        Web interface port (default: $DEFAULT_WEB_PORT)"
    echo "  --db-type TYPE         Database type: postgresql, sqlite (default: $DEFAULT_DB_TYPE)"
    echo "  --db-host HOST         Database host (default: $DEFAULT_DB_HOST)"
    echo "  --db-port PORT         Database port (default: $DEFAULT_DB_PORT)"
    echo "  --db-name NAME         Database name (default: $DEFAULT_DB_NAME)"
    echo "  --db-user USER         Database user (default: $DEFAULT_DB_USER)"
    echo "  --db-password PASS     Database password (default: $DEFAULT_DB_PASSWORD)"
    echo "  --redis-host HOST      Redis host (default: $DEFAULT_REDIS_HOST)"
    echo "  --redis-port PORT      Redis port (default: $DEFAULT_REDIS_PORT)"
    echo "  --package URL           Server package URL (default: $DEFAULT_SERVER_PACKAGE)"
    echo "  --no-start             Don't start services after installation"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Basic installation"
    echo "  $0 --dir /home/qwarktracker --web-port 8080   # Custom directory and web port"
    echo "  $0 --db-type sqlite                           # Use SQLite instead of PostgreSQL"
    echo "  $0 --package https://example.com/server.zip   # Custom package URL"
}

# Main installation function
main() {
    local install_dir="$DEFAULT_INSTALL_DIR"
    local server_port="$DEFAULT_SERVER_PORT"
    local web_port="$DEFAULT_WEB_PORT"
    local db_type="$DEFAULT_DB_TYPE"
    local db_host="$DEFAULT_DB_HOST"
    local db_port="$DEFAULT_DB_PORT"
    local db_name="$DEFAULT_DB_NAME"
    local db_user="$DEFAULT_DB_USER"
    local db_password="$DEFAULT_DB_PASSWORD"
    local redis_host="$DEFAULT_REDIS_HOST"
    local redis_port="$DEFAULT_REDIS_PORT"
    local server_package="$DEFAULT_SERVER_PACKAGE"
    local no_start=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dir)
                install_dir="$2"
                shift 2
                ;;
            --server-port)
                server_port="$2"
                shift 2
                ;;
            --web-port)
                web_port="$2"
                shift 2
                ;;
            --db-type)
                db_type="$2"
                shift 2
                ;;
            --db-host)
                db_host="$2"
                shift 2
                ;;
            --db-port)
                db_port="$2"
                shift 2
                ;;
            --db-name)
                db_name="$2"
                shift 2
                ;;
            --db-user)
                db_user="$2"
                shift 2
                ;;
            --db-password)
                db_password="$2"
                shift 2
                ;;
            --redis-host)
                redis_host="$2"
                shift 2
                ;;
            --redis-port)
                redis_port="$2"
                shift 2
                ;;
            --package)
                server_package="$2"
                shift 2
                ;;
            --no-start)
                no_start=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
    
    print_status "QwarkTracker Server Installation"
    print_status "Installation Directory: $install_dir"
    print_status "Server Port: $server_port"
    print_status "Web Port: $web_port"
    print_status "Database Type: $db_type"
    echo ""
    
    # Detect OS
    local os_type=$(detect_os)
    print_status "Detected OS: $os_type"
    
    # Check requirements
    check_requirements "$os_type"
    
    # Install dependencies
    install_dependencies "$os_type"
    
    # Create installation directory
    print_status "Creating installation directory..."
    if [ "$os_type" = "linux" ]; then
        sudo mkdir -p "$install_dir"
        sudo chown $USER:$USER "$install_dir"
    else
        mkdir -p "$install_dir"
    fi
    
    # Handle server files - try download first, then local copy
    print_status "Installing server files..."
    
    # First try to download from GitHub
    if download_server_package "$install_dir" "$server_package"; then
        print_success "Server files downloaded and extracted from GitHub"
    else
        # Fallback to local files if available
        if check_local_files; then
            print_status "Using local server files..."
            cp -r . "$install_dir/"
        else
            print_error "No server files available. Please either:"
            print_error "  1. Ensure the server package is accessible at: $server_package"
            print_error "  2. Copy the QwarkTracker project directory to this location"
            print_error "  3. Use --package to specify a different package URL"
            exit 1
        fi
    fi
    
    cd "$install_dir"
    
    # Create environment file
    create_env_file "$install_dir" "$db_type" "$db_host" "$db_port" "$db_name" "$db_user" "$db_password" "$redis_host" "$redis_port" "$server_port" "$web_port"
    
    # Setup database
    setup_database "$install_dir" "$db_type"
    
    # Start services unless disabled
    if [ "$no_start" = false ]; then
        start_services "$install_dir"
        
        # Test installation
        test_installation "$server_port" "$web_port"
        
        print_success "QwarkTracker server installation complete!"
        echo ""
        print_status "Next steps:"
        echo "  1. Access the web interface at http://localhost:${web_port}"
        echo "  2. Login with admin/admin123"
        echo "  3. Start installing clients on your devices"
        echo ""
        print_status "To manage the server:"
        echo "  cd $install_dir"
        local compose_cmd=$(get_docker_compose_cmd)
        echo "  $compose_cmd logs -f     # View logs"
        echo "  $compose_cmd restart     # Restart services"
        echo "  $compose_cmd down         # Stop services"
    else
        print_success "QwarkTracker server installation complete!"
        print_status "To start the server manually:"
        echo "  cd $install_dir"
        local compose_cmd=$(get_docker_compose_cmd)
        echo "  $compose_cmd up -d"
    fi
}

# Run main function with all arguments
main "$@"
