#!/bin/bash

# QwarkTracker Client Auto-Installation Script
# Supports Linux, macOS, and Windows (via WSL)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_SERVER_URL="http://localhost:8000"
DEFAULT_DEVICE_NAME=""
DEFAULT_INSTALL_DIR="/opt/qwarktracker"
DEFAULT_SERVICE_USER="root"
DEFAULT_CLIENT_PACKAGE="https://raw.githubusercontent.com/bowser-2077/CascadeMC/refs/heads/main/client.zip"

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

# Function to download client package from server
download_client_package() {
    local server_url="$1"
    local install_dir="$2"
    local package_url="$3"
    
    print_status "Downloading client package..."
    
    # If package_url is a full URL, use it directly
    if [[ $package_url == http* ]]; then
        local download_url="$package_url"
        local filename=$(basename "$package_url")
    else
        # Otherwise, treat it as relative to server
        local base_url=$(echo $server_url | sed 's|/api/v1||')
        local download_url="${base_url}/${package_url}"
        local filename="$package_url"
    fi
    
    # Try to download the client package
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 30 -L -f "$download_url" -o "${install_dir}/${filename}"; then
            print_success "Client package downloaded from: $download_url"
            
            # Extract the package
            print_status "Extracting client package..."
            cd "$install_dir"
            
            if command -v unzip &> /dev/null; then
                unzip -q "${filename}" -d .
                rm "${filename}"
                print_success "Client package extracted"
                return 0
            else
                print_error "unzip not available, cannot extract package"
                return 1
            fi
        else
            print_warning "Failed to download client package from: $download_url"
            return 1
        fi
    elif command -v wget &> /dev/null; then
        if wget --timeout=30 --tries=3 "$download_url" -O "${install_dir}/${filename}" 2>/dev/null; then
            print_success "Client package downloaded from: $download_url"
            
            # Extract the package
            print_status "Extracting client package..."
            cd "$install_dir"
            
            if command -v unzip &> /dev/null; then
                unzip -q "${filename}" -d .
                rm "${filename}"
                print_success "Client package extracted"
                return 0
            else
                print_error "unzip not available, cannot extract package"
                return 1
            fi
        else
            print_warning "Failed to download client package from: $download_url"
            return 1
        fi
    else
        print_warning "Neither curl nor wget available for download"
        return 1
    fi
}

# Function to check if client files exist locally
check_local_files() {
    print_status "Checking for local client files..."
    
    if [ -f "agent.py" ] && [ -f "config.yaml" ] && [ -f "requirements.txt" ]; then
        print_success "Local client files found"
        return 0
    else
        print_warning "Local client files not complete"
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

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_warning "This script requires root privileges for system metrics access."
        print_warning "Running with sudo..."
        if sudo -n true 2>/dev/null; then
            return 0
        else
            print_error "Please run this script with sudo: sudo ./install-client.sh"
            exit 1
        fi
    fi
}

# Function to install Python dependencies
install_python_deps() {
    print_status "Installing Python dependencies..."
    
    # Try pip3 first, then pip
    if command -v pip3 &> /dev/null; then
        PIP_CMD="pip3"
    elif command -v pip &> /dev/null; then
        PIP_CMD="pip"
    else
        print_error "Neither pip3 nor pip found. Please install Python and pip first."
        exit 1
    fi
    
    # Install requirements
    if [ -f "requirements.txt" ]; then
        $PIP_CMD install -r requirements.txt
        print_success "Python dependencies installed"
    else
        print_error "requirements.txt not found in current directory"
        exit 1
    fi
}

# Function to create systemd service (Linux)
create_systemd_service() {
    local service_name="qwarktracker"
    local service_file="/etc/systemd/system/${service_name}.service"
    
    print_status "Creating systemd service..."
    
    cat << EOF | sudo tee $service_file > /dev/null
[Unit]
Description=QwarkTracker Client Agent
Documentation=https://github.com/your-repo/qwarktracker
After=network.target
Wants=network.target

[Service]
Type=simple
User=$DEFAULT_SERVICE_USER
Group=$DEFAULT_SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/agent.py
ExecReload=/bin/kill -HUP \$MAINPID
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=qwarktracker

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable $service_name
    print_success "Systemd service created and enabled"
}

# Function to create macOS LaunchAgent
create_macos_launchagent() {
    local plist_file="$HOME/Library/LaunchAgents/com.qwarktracker.agent.plist"
    
    print_status "Creating macOS LaunchAgent..."
    
    cat << EOF > $plist_file
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.qwarktracker.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$INSTALL_DIR/agent.py</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$INSTALL_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$INSTALL_DIR/qwarktracker.log</string>
    <key>StandardErrorPath</key>
    <string>$INSTALL_DIR/qwarktracker.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PYTHONPATH</key>
        <string>$INSTALL_DIR</string>
    </dict>
</dict>
</plist>
EOF

    launchctl load $plist_file
    print_success "macOS LaunchAgent created and loaded"
}

# Function to configure client
configure_client() {
    local server_url="$1"
    local device_name="$2"
    
    print_status "Configuring client..."
    
    # Update config.yaml with server URL
    if [ -f "config.yaml" ]; then
        sed -i.bak "s|url:.*|url: \"$server_url\"|g" config.yaml
        sed -i.bak "s|name:.*|name: \"$device_name\"|g" config.yaml
        print_success "Client configuration updated"
    else
        print_error "config.yaml not found"
        exit 1
    fi
}

# Function to test connection
test_connection() {
    local server_url="$1"
    
    print_status "Testing connection to server..."
    
    # Extract host from URL
    local host=$(echo $server_url | sed 's|https\?://||' | cut -d: -f1)
    local port=$(echo $server_url | sed 's|.*:\([0-9]*\).*|\1|')
    
    if [ "$port" = "$server_url" ]; then
        port="80"
    fi
    
    # Test connectivity
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 10 "$server_url/health" > /dev/null; then
            print_success "Connection to server successful"
            return 0
        else
            print_warning "Cannot connect to server at $server_url"
            print_warning "Please check:"
            print_warning "  - Server is running"
            print_warning "  - Network connectivity"
            print_warning "  - Firewall settings"
            return 1
        fi
    else
        print_warning "curl not available, skipping connection test"
        return 0
    fi
}

# Function to start service
start_service() {
    local os_type="$1"
    
    print_status "Starting QwarkTracker service..."
    
    case $os_type in
        "linux")
            if sudo systemctl start qwarktracker; then
                print_success "Service started"
                sudo systemctl status qwarktracker --no-pager -l
            else
                print_error "Failed to start service"
                return 1
            fi
            ;;
        "macos")
            if launchctl start com.qwarktracker.agent; then
                print_success "LaunchAgent started"
            else
                print_error "Failed to start LaunchAgent"
                return 1
            fi
            ;;
        *)
            print_warning "Manual start required: python3 $INSTALL_DIR/agent.py"
            ;;
    esac
}

# Function to show status
show_status() {
    local os_type="$1"
    
    print_status "Service status:"
    
    case $os_type in
        "linux")
            sudo systemctl status qwarktracker --no-pager -l
            ;;
        "macos")
            launchctl list | grep qwarktracker
            ;;
        *)
            print_status "Check logs: tail -f $INSTALL_DIR/qwarktracker.log"
            ;;
    esac
}

# Function to display usage
usage() {
    echo "QwarkTracker Client Installation Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -s, --server URL     Server URL (default: $DEFAULT_SERVER_URL)"
    echo "  -n, --name NAME      Device name (default: auto-generated)"
    echo "  -d, --dir DIR        Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  -u, --user USER      Service user (default: $DEFAULT_SERVICE_USER)"
    echo "  -p, --package FILE   Client package name (default: $DEFAULT_CLIENT_PACKAGE)"
    echo "  --no-service         Don't install as service"
    echo "  --test-only          Only test connection, don't install"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -s http://192.168.1.100:8000 -n web-server-01"
    echo "  $0 --server https://monitor.company.com --name db-primary"
    echo "  $0 --test-only -s http://server:8000"
    echo "  $0 -p https://raw.githubusercontent.com/bowser-2077/CascadeMC/refs/heads/main/client.zip -s http://server:8000"
}

# Main installation function
main() {
    local server_url="$DEFAULT_SERVER_URL"
    local device_name="$DEFAULT_DEVICE_NAME"
    local install_dir="$DEFAULT_INSTALL_DIR"
    local service_user="$DEFAULT_SERVICE_USER"
    local client_package="$DEFAULT_CLIENT_PACKAGE"
    local no_service=false
    local test_only=false
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--server)
                server_url="$2"
                shift 2
                ;;
            -n|--name)
                device_name="$2"
                shift 2
                ;;
            -d|--dir)
                install_dir="$2"
                shift 2
                ;;
            -u|--user)
                service_user="$2"
                shift 2
                ;;
            -p|--package)
                client_package="$2"
                shift 2
                ;;
            --no-service)
                no_service=true
                shift
                ;;
            --test-only)
                test_only=true
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
    
    # Generate device name if not provided
    if [ -z "$device_name" ]; then
        device_name="device-$(hostname)-$(date +%s)"
        print_status "Using auto-generated device name: $device_name"
    fi
    
    # Detect operating system
    local os_type=$(detect_os)
    print_status "Detected OS: $os_type"
    
    # Test connection if requested
    if [ "$test_only" = true ]; then
        test_connection "$server_url"
        exit $?
    fi
    
    print_status "Starting QwarkTracker client installation..."
    print_status "Server URL: $server_url"
    print_status "Device Name: $device_name"
    print_status "Install Directory: $install_dir"
    
    # Test connection first
    if ! test_connection "$server_url"; then
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # Check prerequisites
    if [ "$os_type" = "linux" ] && [ "$no_service" = false ]; then
        check_root
    fi
    
    # Check if Python is available
    if ! command -v python3 &> /dev/null && ! command -v python &> /dev/null; then
        print_error "Python 3 is required but not installed"
        exit 1
    fi
    
    # Create installation directory
    print_status "Creating installation directory..."
    if [ "$os_type" = "linux" ]; then
        sudo mkdir -p "$install_dir"
        sudo chown $service_user:$service_user "$install_dir"
    else
        mkdir -p "$install_dir"
    fi
    
    # Handle client files - try download first, then local copy
    print_status "Installing client files..."
    
    # First try to download from server
    if download_client_package "$server_url" "$install_dir" "$client_package"; then
        print_success "Client files downloaded and extracted from server"
    else
        # Fallback to local files if available
        if check_local_files; then
            print_status "Using local client files..."
            cp -r . "$install_dir/"
        else
            print_error "No client files available. Please either:"
            print_error "  1. Ensure the client package is accessible at: $client_package"
            print_error "  2. Copy client/ directory to this location"
            print_error "  3. Run this script from within the client directory"
            print_error "  4. Use -p to specify a different package URL"
            exit 1
        fi
    fi
    
    cd "$install_dir"
    
    # Install Python dependencies
    install_python_deps
    
    # Configure client
    configure_client "$server_url" "$device_name"
    
    # Create service if requested
    if [ "$no_service" = false ]; then
        case $os_type in
            "linux")
                create_systemd_service
                ;;
            "macos")
                create_macos_launchagent
                ;;
            *)
                print_warning "Service creation not supported on $os_type"
                ;;
        esac
    fi
    
    # Start service
    if [ "$no_service" = false ]; then
        start_service "$os_type"
    else
        print_status "Run manually: python3 $install_dir/agent.py"
    fi
    
    # Show final status
    echo ""
    print_success "Installation completed!"
    echo ""
    echo "Installation Summary:"
    echo "  Device Name: $device_name"
    echo "  Server: $server_url"
    echo "  Install Directory: $install_dir"
    echo "  Config File: $install_dir/config.yaml"
    echo "  Log File: $install_dir/qwarktracker.log"
    echo ""
    
    if [ "$no_service" = false ]; then
        echo "Service Management:"
        case $os_type in
            "linux")
                echo "  Start: sudo systemctl start qwarktracker"
                echo "  Stop: sudo systemctl stop qwarktracker"
                echo "  Status: sudo systemctl status qwarktracker"
                echo "  Logs: sudo journalctl -u qwarktracker -f"
                ;;
            "macos")
                echo "  Start: launchctl start com.qwarktracker.agent"
                echo "  Stop: launchctl stop com.qwarktracker.agent"
                echo "  Status: launchctl list | grep qwarktracker"
                echo "  Logs: tail -f $install_dir/qwarktracker.log"
                ;;
        esac
    fi
    
    echo ""
    echo "Next Steps:"
    echo "  1. Check the device appears in your QwarkTracker web interface"
    echo "  2. Verify metrics are being collected (wait 30-60 seconds)"
    echo "  3. Configure alert rules if needed"
    echo ""
    
    # Show current status
    if [ "$no_service" = false ]; then
        echo "Current Status:"
        show_status "$os_type"
    fi
}

# Run main function with all arguments
main "$@"
