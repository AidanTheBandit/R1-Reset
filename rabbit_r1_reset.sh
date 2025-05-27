#!/bin/bash

# Rabbit R1 Factory Reset Script with Automatic Setup
# This script automatically installs MTKClient and performs factory reset
# Compatible with Linux, macOS, and Windows (WSL/Git Bash)

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MTKCLIENT_DIR="$SCRIPT_DIR/mtkclient"
VENV_DIR="$SCRIPT_DIR/mtk_venv"
MTK_CMD=""
IS_LIVE_DVD=false

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

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Function to detect system type
detect_system() {
    if [ -f "/etc/os-release" ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    elif [ -f "/etc/redhat-release" ]; then
        OS="rhel"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS="macos"
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        OS="windows"
    else
        OS="unknown"
    fi
    
    # Check if running on MTK Live DVD
    if [ "$USER" = "user" ] && [ -d "/opt/mtkclient" ]; then
        IS_LIVE_DVD=true
        print_success "MTK Live DVD environment detected"
    fi
    
    print_status "Detected OS: $OS"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install system dependencies
install_system_deps() {
    print_step "Installing system dependencies..."
    
    case $OS in
        ubuntu|debian)
            print_status "Installing dependencies for Ubuntu/Debian..."
            sudo apt update
            sudo apt install -y python3 python3-pip python3-venv git libusb-1.0-0 libfuse2 curl wget build-essential
            ;;
        arch|manjaro)
            print_status "Installing dependencies for Arch Linux..."
            sudo pacman -S --noconfirm python python-pip python-pipenv git libusb fuse2 curl wget base-devel
            ;;
        fedora|rhel|centos)
            print_status "Installing dependencies for Fedora/RHEL..."
            sudo dnf install -y python3 python3-pip git libusb1 fuse curl wget gcc gcc-c++ make
            ;;
        macos)
            print_status "Installing dependencies for macOS..."
            if ! command_exists brew; then
                print_status "Installing Homebrew..."
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            brew install macfuse openssl python@3.9 git
            ;;
        windows)
            print_warning "Windows detected. Please ensure the following are installed:"
            echo "  - Python 3.9+ from python.org (NOT Microsoft Store)"
            echo "  - Git for Windows"
            echo "  - Visual Studio Build Tools (C++ workload)"
            echo "  - WinFsp from https://winfsp.dev/rel/"
            echo "  - UsbDk from https://github.com/daynix/UsbDk/releases/"
            read -p "Press Enter once all prerequisites are installed..."
            ;;
        *)
            print_error "Unsupported operating system: $OS"
            print_error "Please install dependencies manually:"
            echo "  - Python 3.8+"
            echo "  - pip"
            echo "  - git"
            echo "  - libusb"
            echo "  - fuse"
            exit 1
            ;;
    esac
}

# Function to setup user permissions (Linux only)
setup_permissions() {
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" || "$OS" == "arch" || "$OS" == "fedora" ]]; then
        print_step "Setting up user permissions..."
        
        # Add user to required groups
        sudo usermod -a -G plugdev $USER 2>/dev/null || true
        sudo usermod -a -G dialout $USER 2>/dev/null || true
        
        # Install udev rules
        if [ -f "$MTKCLIENT_DIR/mtkclient/Setup/Linux/51-edl.rules" ]; then
            print_status "Installing udev rules..."
            sudo cp "$MTKCLIENT_DIR/mtkclient/Setup/Linux/"*.rules /etc/udev/rules.d/ 2>/dev/null || true
            sudo udevadm control -R 2>/dev/null || true
            sudo udevadm trigger 2>/dev/null || true
        fi
        
        # Check if blacklist is needed
        if lsusb | grep -q "0x0E8D"; then
            echo "blacklist qcaux" | sudo tee -a /etc/modprobe.d/blacklist.conf >/dev/null 2>&1 || true
        fi
        
        print_warning "You may need to log out and log back in for group changes to take effect"
    fi
}

# Function to clone MTKClient repository
clone_mtkclient() {
    print_step "Downloading MTKClient..."
    
    if [ -d "$MTKCLIENT_DIR" ]; then
        print_status "MTKClient directory exists, updating..."
        cd "$MTKCLIENT_DIR"
        git pull origin main || git pull origin master
    else
        print_status "Cloning MTKClient repository..."
        git clone https://github.com/bkerler/mtkclient.git "$MTKCLIENT_DIR"
        cd "$MTKCLIENT_DIR"
    fi
}

# Function to setup Python virtual environment
setup_venv() {
    print_step "Setting up Python virtual environment..."
    
    # Create virtual environment
    if [ ! -d "$VENV_DIR" ]; then
        python3 -m venv "$VENV_DIR"
    fi
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install MTKClient dependencies
    cd "$MTKCLIENT_DIR"
    pip install -r requirements.txt
    pip install .
    
    # Set MTK command for virtual environment
    MTK_CMD="$VENV_DIR/bin/python -m mtkclient.mtk"
}

# Function to setup MTKClient without venv (for Live DVD or system install)
setup_mtkclient_direct() {
    print_step "Setting up MTKClient..."
    
    cd "$MTKCLIENT_DIR"
    
    if command_exists pip3; then
        pip3 install --user -r requirements.txt
        pip3 install --user .
        MTK_CMD="python3 -m mtkclient.mtk"
    elif command_exists pip; then
        pip install --user -r requirements.txt
        pip install --user .
        MTK_CMD="python -m mtkclient.mtk"
    else
        # Fallback to direct execution
        MTK_CMD="python3 mtk.py"
    fi
}

# Function to verify MTKClient installation
verify_mtkclient() {
    print_step "Verifying MTKClient installation..."
    
    # Test different command variations
    local test_commands=(
        "$MTK_CMD --help"
        "python3 $MTKCLIENT_DIR/mtk.py --help"
        "$MTKCLIENT_DIR/mtk.py --help"
        "/opt/mtkclient/mtk --help"
    )
    
    for cmd in "${test_commands[@]}"; do
        if eval "$cmd" >/dev/null 2>&1; then
            if [[ $cmd == *"--help" ]]; then
                MTK_CMD="${cmd% --help}"
            fi
            print_success "MTKClient is working: $MTK_CMD"
            return 0
        fi
    done
    
    print_error "MTKClient installation verification failed"
    return 1
}

# Function to download precompiled tools (if available)
download_precompiled() {
    print_step "Checking for precompiled binaries..."
    
    local arch=$(uname -m)
    local os_name=""
    
    case $OS in
        ubuntu|debian) os_name="linux" ;;
        macos) os_name="darwin" ;;
        windows) os_name="windows" ;;
        *) return 1 ;;
    esac
    
    # This is a placeholder for future precompiled binaries
    # The MTKClient project doesn't currently provide them
    print_status "Precompiled binaries not available, using source installation"
    return 1
}

# Function to perform automatic setup
auto_setup() {
    print_step "Starting automatic setup..."
    
    # Skip setup if already on Live DVD
    if [ "$IS_LIVE_DVD" = true ]; then
        print_success "Running on MTK Live DVD - setup not needed"
        MTK_CMD="/opt/mtkclient/mtk"
        return 0
    fi
    
    # Install system dependencies
    if ! download_precompiled; then
        install_system_deps
        clone_mtkclient
        
        # Choose setup method based on system
        if [[ "$OS" == "macos" ]] || [ "$USER" != "root" ]; then
            setup_venv
        else
            setup_mtkclient_direct
        fi
        
        setup_permissions
    fi
    
    # Verify installation
    if ! verify_mtkclient; then
        print_error "Setup failed - MTKClient not working properly"
        exit 1
    fi
    
    print_success "Automatic setup completed successfully!"
}

# Function to display banner
show_banner() {
    echo -e "${BLUE}"
    echo "========================================================"
    echo "    Rabbit R1 Auto-Setup Factory Reset Tool v2.0"
    echo "         Automatic MTKClient Installation"
    echo "========================================================"
    echo -e "${NC}"
}

# Function to show warnings and get user confirmation
show_warnings() {
    echo -e "${RED}"
    echo "⚠️  WARNING: AUTOMATIC SETUP & FACTORY RESET ⚠️"
    echo "========================================================"
    echo "This script will:"
    echo "• Automatically install MTKClient and dependencies"
    echo "• Set up required permissions and drivers"
    echo "• Erase ALL user data on your Rabbit R1"
    echo "• Reset the device to factory settings"
    echo "• Bypass lost mode if activated"
    echo "• Cannot be undone once started"
    echo "========================================================"
    echo -e "${NC}"
    
    echo -e "${YELLOW}What will be installed:${NC}"
    if [ "$IS_LIVE_DVD" != true ]; then
        echo "• System dependencies (Python, Git, USB libraries)"
        echo "• MTKClient from GitHub"
        echo "• Python virtual environment"
        echo "• USB device rules and permissions"
    else
        echo "• Nothing - Live DVD environment detected"
    fi
    echo ""
    
    echo -e "${YELLOW}Prerequisites:${NC}"
    echo "• Internet connection for downloads"
    echo "• Administrator/sudo access (except Live DVD)"
    echo "• Rabbit R1 device with USB cable"
    echo ""
    
    read -p "Do you want to continue with automatic setup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Operation cancelled by user"
        exit 0
    fi
}

# Function to prepare device for connection
prepare_device() {
    print_step "Preparing for device connection..."
    echo ""
    echo -e "${YELLOW}Device Connection Instructions:${NC}"
    echo "1. Ensure your Rabbit R1 is completely powered off"
    echo "2. Connect the USB cable between R1 and computer"
    echo "3. When prompted, the script will wait for device connection"
    echo "4. After connection is detected, plug in your R1"
    echo ""
    read -p "Press Enter when ready to proceed..."
}

# Function to perform the factory reset
perform_reset() {
    print_step "Starting factory reset process..."
    print_status "Waiting for device connection..."
    
    echo -e "${YELLOW}"
    echo "🔌 PLUG IN YOUR RABBIT R1 NOW!"
    echo "   The device should be detected automatically"
    echo "   You'll see dots appearing as the tool waits..."
    echo -e "${NC}"
    
    # Activate virtual environment if it exists
    if [ -f "$VENV_DIR/bin/activate" ]; then
        source "$VENV_DIR/bin/activate"
    fi
    
    # Execute the MTK command to erase userdata partition
    print_status "Executing: $MTK_CMD e userdata"
    
    # Change to MTKClient directory for execution
    cd "$MTKCLIENT_DIR" 2>/dev/null || cd "$SCRIPT_DIR"
    
    if eval "$MTK_CMD e userdata"; then
        print_success "Userdata partition erased successfully!"
        return 0
    else
        print_error "Failed to erase userdata partition"
        return 1
    fi
}

# Function to provide post-reset instructions
post_reset_instructions() {
    echo ""
    echo -e "${GREEN}"
    echo "✅ Factory Reset Complete!"
    echo "=========================="
    echo -e "${NC}"
    
    echo -e "${YELLOW}Next Steps:${NC}"
    echo "1. Unplug the USB cable from your Rabbit R1"
    echo "2. Hold the power button to turn on the device"
    echo "3. The R1 should boot to initial setup screen"
    echo "4. Follow on-screen instructions to set up your device"
    echo ""
    
    print_success "Your Rabbit R1 has been successfully factory reset!"
    print_status "Lost mode has been bypassed and all user data cleared"
    
    if [ "$IS_LIVE_DVD" != true ]; then
        echo ""
        echo -e "${CYAN}Setup Information:${NC}"
        echo "• MTKClient installed in: $MTKCLIENT_DIR"
        if [ -d "$VENV_DIR" ]; then
            echo "• Python environment: $VENV_DIR"
            echo "• To use MTKClient again: source $VENV_DIR/bin/activate"
        fi
        echo "• You can run this script again anytime"
    fi
}

# Function to handle errors with detailed troubleshooting
handle_error() {
    print_error "An error occurred during the process"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo ""
    echo -e "${CYAN}Setup Issues:${NC}"
    echo "• Run with sudo if permission errors occur"
    echo "• Ensure internet connection for downloads"
    echo "• Check if Python 3.8+ is properly installed"
    echo ""
    echo -e "${CYAN}Device Issues:${NC}"
    echo "• Ensure device drivers are properly installed"
    echo "• Try a different USB cable or port"
    echo "• Make sure the R1 is completely powered off before connecting"
    echo "• On Linux, logout and login after first run (for group permissions)"
    echo ""
    echo -e "${CYAN}Windows Specific:${NC}"
    echo "• Install UsbDk drivers from: https://github.com/daynix/UsbDk/releases/"
    echo "• Install Visual Studio Build Tools with C++ workload"
    echo "• Use Python from python.org, NOT Microsoft Store"
    echo ""
    echo "For more help, visit: https://github.com/bkerler/mtkclient"
    echo "Or use the MTK Live DVD: https://androidfilehost.com/?fid=15664248565197184488"
}

# Function to cleanup on exit
cleanup() {
    if [ -f "$VENV_DIR/bin/activate" ]; then
        deactivate 2>/dev/null || true
    fi
}

# Function to check internet connectivity
check_internet() {
    print_step "Checking internet connectivity..."
    
    if command_exists curl; then
        if curl -s --connect-timeout 5 https://github.com >/dev/null; then
            print_success "Internet connection verified"
            return 0
        fi
    elif command_exists wget; then
        if wget -q --spider --timeout=5 https://github.com; then
            print_success "Internet connection verified"
            return 0
        fi
    fi
    
    print_error "No internet connection detected"
    print_error "Internet is required for automatic setup"
    exit 1
}

# Main execution function
main() {
    show_banner
    detect_system
    show_warnings
    
    if [ "$IS_LIVE_DVD" != true ]; then
        check_internet
    fi
    
    auto_setup
    prepare_device
    
    if perform_reset; then
        post_reset_instructions
    else
        handle_error
        exit 1
    fi
}

# Trap to handle script interruption and cleanup
trap 'echo -e "\n${RED}Script interrupted by user${NC}"; cleanup; exit 130' INT
trap 'cleanup' EXIT

# Check if script is run with bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Please run with: bash $0"
    exit 1
fi

# Run main function
main "$@"