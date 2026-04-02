#!/bin/bash

# QwarkTracker Server Manual Installation Script (No Docker)
# For systems without Docker - installs directly with Python

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_INSTALL_DIR="/opt/qwarktracker"
DEFAULT_SERVER_PORT="8000"
DEFAULT_WEB_PORT="3000"
DEFAULT_DB_TYPE="sqlite"
DEFAULT_DB_NAME="qwarktracker.db"
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
    
    if [ -f "server/app/main.py" ] && [ -f "start.sh" ]; then
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

# Function to check system requirements
check_requirements() {
    local os_type="$1"
    
    print_status "Checking system requirements..."
    
    # Check Python
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed"
        print_status "Please install Python 3: https://www.python.org/downloads/"
        exit 1
    fi
    
    # Check pip
    if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &> /dev/null; then
        print_error "pip is required but not installed"
        print_status "Please install pip: https://pip.pypa.io/en/stable/installation/"
        exit 1
    fi
    
    # Check Node.js (for web interface)
    if ! command -v node &> /dev/null; then
        print_warning "Node.js is recommended for web interface but not installed"
        print_status "Please install Node.js: https://nodejs.org/"
        print_status "Or use the API-only mode"
    fi
    
    print_success "System requirements met"
}

# Function to install Python dependencies
install_python_deps() {
    local install_dir="$1"
    
    print_status "Installing Python dependencies..."
    
    # Check if server directory exists
    if [ ! -d "$install_dir/server" ]; then
        print_error "Server directory not found in $install_dir"
        print_status "Available directories:"
        ls -la "$install_dir"
        exit 1
    fi
    
    cd "$install_dir/server"
    
    # Install server dependencies
    if python3 -m pip install -r requirements.txt; then
        print_success "Python dependencies installed"
    else
        print_error "Failed to install Python dependencies"
        exit 1
    fi
}

# Function to setup database
setup_database() {
    local install_dir="$1"
    local db_type="$2"
    local db_name="$3"
    
    print_status "Setting up database..."
    
    cd "$install_dir"
    
    if [ "$db_type" = "sqlite" ]; then
        print_status "Setting up SQLite database..."
        
        # Create database directory
        mkdir -p data
        
        # Initialize database
        if [ -f "database/schema.sql" ]; then
            sqlite3 "data/$db_name" < database/schema.sql
            print_success "SQLite database initialized"
        else
            print_warning "Database schema not found, will be created automatically"
        fi
        
    elif [ "$db_type" = "postgresql" ]; then
        print_status "PostgreSQL setup requires manual configuration:"
        echo "  1. Install PostgreSQL: sudo apt-get install postgresql postgresql-contrib"
        echo "  2. Create database: createdb qwarktracker"
        echo "  3. Create user: createuser qwarktracker"
        echo "  4. Set password: psql -c \"ALTER USER qwarktracker PASSWORD 'your_password';\""
        echo "  5. Import schema: psql -U qwarktracker -d qwarktracker < database/schema.sql"
        print_warning "Please complete PostgreSQL setup manually"
    fi
}

# Function to create environment file
create_env_file() {
    local install_dir="$1"
    local db_type="$2"
    local db_name="$3"
    local server_port="$4"
    local web_port="$5"
    
    print_status "Creating environment configuration..."
    
    local env_file="$install_dir/.env"
    
    # Generate secret key
    local secret_key=$(openssl rand -hex 32 2>/dev/null || date +%s | sha256sum | base64 | head -c 32)
    
    cat > "$env_file" << EOF
# QwarkTracker Server Configuration (Manual Installation)
DATABASE_URL=${db_type}:///$(pwd)/data/${db_name}
SECRET_KEY=${secret_key}

# API Configuration
API_HOST=0.0.0.0
API_PORT=${server_port}
API_RELOAD=true
API_WORKERS=1

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

# Redis (optional - for production)
REDIS_URL=redis://localhost:6379

# Celery (optional - for production)
CELERY_BROKER_URL=redis://localhost:6379/0
CELERY_RESULT_BACKEND=redis://localhost:6379/0
EOF

    print_success "Environment file created at $env_file"
}

# Function to create startup scripts
create_startup_scripts() {
    local install_dir="$1"
    local server_port="$2"
    local web_port="$3"
    
    print_status "Creating startup scripts..."
    
    # Create server startup script
    cat > "$install_dir/start-server.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")"
export $(cat .env | xargs)
cd server
python3 -m uvicorn app.main:app --host $API_HOST --port $API_PORT --reload
EOF

    # Create web startup script (if Node.js available)
    if command -v node &> /dev/null; then
        cat > "$install_dir/start-web.sh" << 'EOF'
#!/bin/bash
cd "$(dirname "$0")/web"
npm start
EOF
        chmod +x "$install_dir/start-web.sh"
    fi
    
    chmod +x "$install_dir/start-server.sh"
    print_success "Startup scripts created"
}

# Function to test installation
test_installation() {
    local server_port="$1"
    
    print_status "Testing installation..."
    
    # Wait a bit for server to start
    sleep 5
    
    # Test API
    if curl -s -f "http://localhost:${server_port}/health" > /dev/null 2>&1; then
        print_success "API is responding"
    else
        print_warning "API not yet responding (may need manual start)"
    fi
}

# Function to show usage
usage() {
    echo "QwarkTracker Server Manual Installation Script (No Docker)"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --dir DIR          Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  --server-port PORT     API server port (default: $DEFAULT_SERVER_PORT)"
    echo "  --web-port PORT        Web interface port (default: $DEFAULT_WEB_PORT)"
    echo "  --db-type TYPE         Database type: sqlite, postgresql (default: $DEFAULT_DB_TYPE)"
    echo "  --db-name NAME         Database name (default: $DEFAULT_DB_NAME)"
    echo "  --package URL          Server package URL (default: $DEFAULT_SERVER_PACKAGE)"
    echo "  --no-start             Don't start services after installation"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                              # Basic installation"
    echo "  $0 --dir /home/qwarktracker --web-port 8080   # Custom directory and web port"
    echo "  $0 --db-type postgresql                       # Use PostgreSQL"
    echo "  $0 --package https://example.com/server.zip     # Custom package URL"
}

# Main installation function
main() {
    local install_dir="$DEFAULT_INSTALL_DIR"
    local server_port="$DEFAULT_SERVER_PORT"
    local web_port="$DEFAULT_WEB_PORT"
    local db_type="$DEFAULT_DB_TYPE"
    local db_name="$DEFAULT_DB_NAME"
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
            --db-name)
                db_name="$2"
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
    
    print_status "QwarkTracker Server Manual Installation"
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
    
    # Create installation directory
    print_status "Creating installation directory..."
    if [ "$os_type" = "linux" ]; then
        if [ "$EUID" -ne 0 ]; then
            print_warning "This script requires root privileges for installation directory creation."
            print_warning "Running with sudo..."
            sudo "$0" "$@"
            exit $?
        else
            mkdir -p "$install_dir"
            chown $USER:$USER "$install_dir"
        fi
    else
        mkdir -p "$install_dir"
    fi
    
    # Verify directory was created
    if [ ! -d "$install_dir" ]; then
        print_error "Failed to create installation directory: $install_dir"
        exit 1
    fi
    
    # Handle server files - try download first, then local copy
    print_status "Installing server files..."
    
    # First try to download from GitHub
    if download_server_package "$install_dir" "$server_package"; then
        print_success "Server files downloaded and extracted from GitHub"
        print_status "Contents of installation directory:"
        ls -la "$install_dir"
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
    
    # Install Python dependencies
    install_python_deps "$install_dir"
    
    # Setup database
    setup_database "$install_dir" "$db_type" "$db_name"
    
    # Create environment file
    create_env_file "$install_dir" "$db_type" "$db_name" "$server_port" "$web_port"
    
    # Create startup scripts
    create_startup_scripts "$install_dir" "$server_port" "$web_port"
    
    # Start services unless disabled
    if [ "$no_start" = false ]; then
        print_status "Starting QwarkTracker server..."
        
        # Start server in background
        cd "$install_dir"
        ./start-server.sh &
        SERVER_PID=$!
        
        print_success "QwarkTracker server started with PID: $SERVER_PID"
        
        # Test installation
        test_installation "$server_port"
        
        print_success "QwarkTracker server installation complete!"
        echo ""
        print_status "Access URLs:"
        echo "  API: http://localhost:${server_port}"
        echo "  API Docs: http://localhost:${server_port}/docs"
        echo ""
        print_status "Default Login:"
        echo "  Username: admin"
        echo "  Password: admin123"
        echo ""
        print_status "Management Commands:"
        echo "  Start server: cd $install_dir && ./start-server.sh"
        echo "  Stop server: kill $SERVER_PID"
        echo "  View logs: tail -f server.log"
        
        if command -v node &> /dev/null; then
            echo ""
            print_status "Web Interface:"
            echo "  Start web: cd $install_dir && ./start-web.sh"
            echo "  Web URL: http://localhost:${web_port}"
        else
            echo ""
            print_warning "Web interface requires Node.js installation"
            print_status "Install Node.js: https://nodejs.org/"
        fi
    else
        print_success "QwarkTracker server installation complete!"
        print_status "To start the server manually:"
        echo "  cd $install_dir"
        echo "  ./start-server.sh"
    fi
}

# Run main function with all arguments
main "$@"
