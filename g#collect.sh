#!/bin/bash

################################################################################
# g#collect - Hardware Performance and Usage Data Collection Script
#
# Copyright (c) 2025 Cirrus360. All Rights Reserved.
# Contains Cirrus360 CONFIDENTIAL AND PROPRIETARY INFORMATION. Subject to Non-Disclosure Agreement (NDA) with Cirrus360.
#
# The code and information in this file and all associated documentation ("Material") are owned by Cirrus360.
# This material may not be reproduced, displayed, modified, or
# distributed without the express prior written permission of Cirrus360.
# 
# No license under any patent, copyright, trade secret or other intellectual property right
# is granted to or conferred by disclosure or delivery of the Materials. Any license under such
# intellectual property rights must be separately granted by Cirrus360 in writing.

# This notice may not be removed or altered in any way.
################################################################################

################################################################################
# CONFIGURATION PARAMETERS
# Edit these values as needed before running the script
################################################################################

# Perf events to record (comma-separated)
# Common combinations:
#   - Basic: "cycles,instructions,cache-misses"
#   - Detailed: "cycles,instructions,L1-dcache-load-misses,LLC-load-misses"
PERF_EVENTS="cycles/period=100000/,instructions/period=100000/,L1-dcache-load-misses/period=10000/,LLC-load-misses/period=10000/"

# Collection duration in seconds (0 = manual stop only with Ctrl+C)
COLLECTION_DURATION=0

# User-provided label for output files (optional, but recommended)
# Examples: "5g_test_run1", "peak_throughput_test", "ul_64qam"
TEST_LABEL=""

# Output directory (default: current directory)
OUTPUT_DIR="."

# Core selection mode: "auto" (detect isolated cores) or "manual"
CORE_MODE="auto"

# Manual core specification (only used if CORE_MODE="manual")
# Example: "1-30,33-62"
MANUAL_CORES=""

# Additional perf record options
# -T: Record timestamps for each sample
PERF_EXTRA_OPTS="-T"

# Include turbostat output (yes/no)
INCLUDE_TURBOSTAT="yes"

# Turbostat sample iterations (if included)
# Turbostat will collect data for this many times during info gathering phase
TURBOSTAT_ITERATIONS=5

# Create bundle tarball at the end (yes/no)
# When enabled, creates a .tar.gz containing all output files for easy transfer
CREATE_BUNDLE="yes"

# Create symbol archive (yes/no)
# When enabled, runs "perf archive" to create a .tar.bz2 with all symbols
# Note: This is usually not needed for production binaries compiled with -O3
CREATE_SYMBOL_ARCHIVE="no"

################################################################################
# END OF CONFIGURATION
################################################################################

# Script metadata
SCRIPT_VERSION="1.0.1"
SCRIPT_NAME="g#collect"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
PERF_PID=""
INFO_FILE=""
PERF_FILE=""
BUNDLE_FILE=""
CLEANUP_DONE=0
TARGET_CORES=""

################################################################################
# FUNCTIONS
################################################################################

print_help() {
    cat << EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} - Performance Data Collection Script

DESCRIPTION:
    Collects performance data using perf and system information for analysis.
    Designed to run during 5G test scenarios to 
    capture CPU performance metrics.

USAGE:
    sudo ./g#collect.sh [OPTIONS]

OPTIONS:
    -h, --help          Show this help message and exit

CONFIGURATION:
    All parameters are configured by editing the variables at the top of this
    script. Do NOT use command-line switches for configuration.

KEY PARAMETERS:
    PERF_EVENTS         Events to record (e.g., cycles,instructions,cache-misses)
    COLLECTION_DURATION Duration in seconds (0 = manual stop only)
    TEST_LABEL          Optional label for output filenames (recommended)
    CORE_MODE           "auto" to detect isolated cores, "manual" for manual spec
    MANUAL_CORES        Core specification if CORE_MODE="manual" (e.g., "1-30,33-62")
    CREATE_BUNDLE       Create tar.gz bundle of all outputs (yes/no)
    CREATE_SYMBOL_ARCHIVE  Create symbol archive (yes/no)

CORE DETECTION:
    In "auto" mode, the script reads /proc/cmdline to detect isolated cores
    (isolcpus= parameter) and automatically collects data from those cores only.
    If no isolated cores are detected, falls back to system-wide collection.

COLLECTION MODES:
    1. Timed collection: Set COLLECTION_DURATION to number of seconds
       Example: COLLECTION_DURATION=60 (collects for 60 seconds)
    
    2. Manual stop: Set COLLECTION_DURATION=0 and stop with Ctrl+C
       Example: COLLECTION_DURATION=0 (press Ctrl+C when test completes)

OUTPUT FILES:
    [LABEL]_perf_YYYYMMDD_HHMMSS.data  - Performance data (perf.data format)
    [LABEL]_info_YYYYMMDD_HHMMSS.txt   - System information and configuration
    
    If CREATE_BUNDLE="yes":
    [LABEL]_gcollect_YYYYMMDD_HHMMSS.tar.gz - Compressed bundle of all files
    
    If CREATE_SYMBOL_ARCHIVE="yes":
    [LABEL]_perf_YYYYMMDD_HHMMSS.data.tar.bz2 - Symbol archive (optional)

TIMING RECOMMENDATIONS:
    For best results with 5G tests:
    
    • Start script BEFORE starting the 5G test
    • For timed mode: Set COLLECTION_DURATION to cover entire test duration
    • For manual mode: Press Ctrl+C immediately after test completes
    • Script will cleanly finalize data collection on Ctrl+C
    
    Example workflow (manual mode):
      1. Edit script: set COLLECTION_DURATION=0 and TEST_LABEL="my_test"
      2. Run: sudo ./gcollect.sh
      3. Wait for "Data collection is now running..." message
      4. Start your 5G test
      5. Wait for test to complete
      6. Press Ctrl+C to stop collection
      7. Transfer the generated .tar.gz bundle for analysis

REQUIREMENTS:
    • Root privileges (or CAP_SYS_ADMIN + CAP_PERFMON capabilities)
    • perf tool installed (linux-tools-common or similar package)
    • lscpu command available (util-linux package)
    • turbostat available if INCLUDE_TURBOSTAT="yes" (linux-tools-common)
    • Sufficient disk space for perf data files (can be 100s of MB)

NOTES:
    • Data collection has small performance impact (<5%)
    • The .data files can be large (100s of MB for long collections)
    • For production binaries (compiled with -O3), symbol archives are typically not needed

EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root or with sudo"
        log_info "Try: sudo $0"
        exit 1
    fi
}

check_dependencies() {
    local missing_deps=0
    
    if ! command -v perf &> /dev/null; then
        log_error "perf tool not found"
        log_error "Install with: apt-get install linux-tools-common linux-tools-\$(uname -r)"
        missing_deps=1
    fi
    
    if ! command -v lscpu &> /dev/null; then
        log_error "lscpu command not found"
        log_error "Install with: apt-get install util-linux"
        missing_deps=1
    fi
    
    if [ "$INCLUDE_TURBOSTAT" = "yes" ] && ! command -v turbostat &> /dev/null; then
        log_warning "turbostat not found. Will skip turbostat collection."
        log_warning "To include turbostat: apt-get install linux-tools-common"
        INCLUDE_TURBOSTAT="no"
    fi
    
    if [ $missing_deps -eq 1 ]; then
        log_error "Missing required dependencies. Please install them and try again."
        exit 1
    fi
}

detect_isolated_cores() {
    log_info "Detecting isolated cores from /proc/cmdline..."
    
    if [ ! -f /proc/cmdline ]; then
        log_error "/proc/cmdline not found"
        return 1
    fi
    
    local cmdline=$(cat /proc/cmdline)
    
    # Look for isolcpus parameter
    local isolcpus_param=$(echo "$cmdline" | grep -oP 'isolcpus=\K[^ ]+' || echo "")
    
    if [ -z "$isolcpus_param" ]; then
        log_warning "No isolated cores found in /proc/cmdline"
        log_warning "Will collect data from all available cores"
        echo "all"
        return 0
    fi

    local isolated_cores=$(echo "$isolcpus_param" | sed -E 's/^([^0-9]*,)?//; s/,[^0-9,\-]+,/,/g')
    
    if [ -z "$isolated_cores" ]; then
        log_warning "Could not parse CPU list from isolcpus parameter: $isolcpus_param"
        log_warning "Will collect data from all available cores"
        echo "all"
        return 0
    fi
    
    log_success "Detected isolated cores: $isolated_cores"
    echo "$isolated_cores"
}

generate_filenames() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local label_part=""
    
    if [ -n "$TEST_LABEL" ]; then
        label_part="${TEST_LABEL}_"
    fi
    
    PERF_FILE="${OUTPUT_DIR}/${label_part}perf_${timestamp}.data"
    INFO_FILE="${OUTPUT_DIR}/${label_part}info_${timestamp}.txt"
    BUNDLE_FILE="${OUTPUT_DIR}/${label_part}gcollect_${timestamp}.tar.gz"
}

write_info_header() {
    cat > "$INFO_FILE" << EOF
################################################################################
# g#collect System Information and Configuration
# Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')
################################################################################

SCRIPT INFORMATION:
  Script Name: ${SCRIPT_NAME}
  Script Version: ${SCRIPT_VERSION}
  Collection Start: $(date '+%Y-%m-%d %H:%M:%S %Z')

COLLECTION CONFIGURATION:
  Perf Events: ${PERF_EVENTS}
  Collection Duration: ${COLLECTION_DURATION}s $([ $COLLECTION_DURATION -eq 0 ] && echo "(manual stop)" || echo "(timed)")
  Test Label: ${TEST_LABEL:-"(none)"}
  Core Mode: ${CORE_MODE}
  Target Cores: ${TARGET_CORES}
  Extra Perf Options: ${PERF_EXTRA_OPTS}
  Include Turbostat: ${INCLUDE_TURBOSTAT}
  Create Bundle: ${CREATE_BUNDLE}
  Create Symbol Archive: ${CREATE_SYMBOL_ARCHIVE}

OUTPUT FILES:
  Performance Data: ${PERF_FILE}
  Info File: ${INFO_FILE}

################################################################################

EOF
}

collect_system_info() {
    log_info "Collecting system information..."
    
    {
        echo ""
        echo "================================================================================"
        echo "KERNEL COMMAND LINE"
        echo "================================================================================"
        cat /proc/cmdline
        echo ""
        echo ""
        
        echo "================================================================================"
        echo "CPU INFORMATION (lscpu)"
        echo "================================================================================"
        lscpu
        echo ""
        echo ""
        
        echo "================================================================================"
        echo "KERNEL VERSION"
        echo "================================================================================"
        uname -a
        echo ""
        echo ""
        
        echo "================================================================================"
        echo "PERF VERSION"
        echo "================================================================================"
        perf --version
        echo ""
        echo ""
        
        if [ "$INCLUDE_TURBOSTAT" = "yes" ]; then
            echo "================================================================================"
            echo "TURBOSTAT OUTPUT (${TURBOSTAT_ITERATIONS} samples)"
            echo "================================================================================"
            turbostat -i 0.001 -n ${TURBOSTAT_ITERATIONS} 2>&1 || echo "Turbostat collection failed"
            echo ""
            echo ""
        fi
    } >> "$INFO_FILE"
    
    log_success "System information collected"
}

cleanup() {
    if [ $CLEANUP_DONE -eq 1 ]; then
        return
    fi
    
    echo ""
    log_info "Cleaning up and finalizing data collection..."
    
    if [ -n "$PERF_PID" ] && kill -0 $PERF_PID 2>/dev/null; then
        log_info "Stopping perf recording (PID: $PERF_PID)..."
        kill -SIGINT $PERF_PID
        wait $PERF_PID 2>/dev/null
    fi

    CLEANUP_DONE=1
    
    # Write collection end time
    if [ -f "$INFO_FILE" ]; then
        {
            echo ""
            echo "================================================================================"
            echo "COLLECTION SUMMARY"
            echo "================================================================================"
            echo "Collection End: $(date '+%Y-%m-%d %H:%M:%S %Z')"
            
            echo "================================================================================"
        } >> "$INFO_FILE"
    fi
    
    # Create symbol archive if enabled
    if [ "$CREATE_SYMBOL_ARCHIVE" = "yes" ] && [ -f "$PERF_FILE" ]; then
        log_info "Creating symbol archive for offline analysis..."
        if perf archive "$PERF_FILE" 2>/dev/null; then
            log_success "Symbol archive created: ${PERF_FILE}.tar.bz2"
        else
            log_warning "Failed to create symbol archive (perf archive not available or failed)"
        fi
    fi
    
    # Create bundle if enabled
    if [ "$CREATE_BUNDLE" = "yes" ]; then
        log_info "Creating bundle tarball..."
        
        local files_to_bundle=""
        
        # Add perf data file
        if [ -f "$PERF_FILE" ]; then
            files_to_bundle="$(basename $PERF_FILE)"
        fi
        
        # Add info file
        if [ -f "$INFO_FILE" ]; then
            files_to_bundle="$files_to_bundle $(basename $INFO_FILE)"
        fi
        
        # Add symbol archive if it exists
        if [ -f "${PERF_FILE}.tar.bz2" ]; then
            files_to_bundle="$files_to_bundle $(basename ${PERF_FILE}.tar.bz2)"
        fi
        
        # Create tarball
        if [ -n "$files_to_bundle" ]; then
            (
                cd "$OUTPUT_DIR"
                if tar czf "$(basename $BUNDLE_FILE)" $files_to_bundle 2>/dev/null; then
                    log_success "Bundle created: ${BUNDLE_FILE}"
                    
                    # Remove individual files to leave only the bundle
                    rm -f $files_to_bundle
                    log_info "Individual files archived into bundle"
                else
                    log_warning "Failed to create bundle tarball"
                fi
            )
        fi
    fi
    
    echo ""
    log_success "Data collection completed!"
    echo ""
    
    # Display output information
    if [ "$CREATE_BUNDLE" = "yes" ] && [ -f "$BUNDLE_FILE" ]; then
        echo "Output bundle:"
        echo "  ${BUNDLE_FILE}"
        echo ""
        echo "Transfer this file for analysis"
    else
        echo "Output files:"
        if [ -f "$PERF_FILE" ]; then
            echo "  Perf data: ${PERF_FILE}"
        fi
        if [ -f "$INFO_FILE" ]; then
            echo "  Info file: ${INFO_FILE}"
        fi
        if [ "$CREATE_SYMBOL_ARCHIVE" = "yes" ] && [ -f "${PERF_FILE}.tar.bz2" ]; then
            echo "  Symbol archive: ${PERF_FILE}.tar.bz2"
        fi
    fi
    echo ""
}

start_perf_collection() {
    local core_spec=""
    
    # Determine core specification
    if [ "$CORE_MODE" = "auto" ]; then
        TARGET_CORES=$(detect_isolated_cores)
        if [ "$TARGET_CORES" != "all" ]; then
            core_spec="-C ${TARGET_CORES}"
        else
            # No isolated cores found, use system-wide collection
            core_spec="-a"
            TARGET_CORES="all (system-wide)"
        fi
    else
        if [ -z "$MANUAL_CORES" ]; then
            log_error "CORE_MODE is 'manual' but MANUAL_CORES is not set"
            log_error "Please set MANUAL_CORES in the configuration section"
            exit 1
        fi
        TARGET_CORES="$MANUAL_CORES"
        core_spec="-C ${MANUAL_CORES}"
    fi

    # Build perf command
    local perf_cmd="perf record -e ${PERF_EVENTS} ${PERF_EXTRA_OPTS} ${core_spec} -o ${PERF_FILE}"
    
    log_info "Starting perf data collection..."
    log_info "Target cores: ${TARGET_CORES}"
    log_info "Command: $perf_cmd"
    
    # Start perf in background
    $perf_cmd &
    PERF_PID=$!
    
    # Check if perf started successfully
    sleep 2
    if ! kill -0 $PERF_PID 2>/dev/null; then
        log_error "Failed to start perf recording"
        
        # Try to get error message
        if [ -f "$PERF_FILE" ]; then
            log_info "Perf data file was created but process exited"
        else
            log_error "No perf.data file was created"
        fi
        
        PERF_PID=""
        return 1
    fi
    
    # Verify perf.data file is being created
    sleep 1
    if [ ! -f "$PERF_FILE" ]; then
        log_error "Perf process is running but no data file created"
        kill -SIGINT $PERF_PID 2>/dev/null
        wait $PERF_PID 2>/dev/null
        PERF_PID=""
        return 1
    fi
    
    log_success "Perf recording started (PID: $PERF_PID)"
    
    if [ $COLLECTION_DURATION -eq 0 ]; then
        log_info "Collection mode: MANUAL STOP"
        log_info "Press Ctrl+C to stop data collection when test is complete"
    else
        log_info "Collection mode: TIMED (${COLLECTION_DURATION}s)"
        log_info "Will automatically stop after ${COLLECTION_DURATION} seconds"
        log_info "Or press Ctrl+C to stop early"
    fi
}

################################################################################
# MAIN
################################################################################

# Parse command line arguments
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    print_help
    exit 0
fi

# Set up signal handlers
trap cleanup SIGINT SIGTERM

# Header
echo ""
echo "================================================================================"
echo "  ${SCRIPT_NAME} v${SCRIPT_VERSION} - Performance Data Collection"
echo "  Copyright (c) 2025 Cirrus360 - Confidential & Proprietary"
echo "================================================================================"
echo ""

# Pre-flight checks
check_root
check_dependencies

# Generate output filenames
generate_filenames

log_info "Output directory: ${OUTPUT_DIR}"
log_info "Perf data file: ${PERF_FILE}"
log_info "Info file: ${INFO_FILE}"
if [ "$CREATE_BUNDLE" = "yes" ]; then
    log_info "Bundle file: ${BUNDLE_FILE}"
fi
echo ""

# Create info file and write header
write_info_header

# Collect system information
collect_system_info

# Start performance data collection
start_perf_collection

# Check if perf started successfully
if [ -z "$PERF_PID" ]; then
    log_error "Failed to start data collection. Exiting."
    exit 1
fi

echo ""
log_success "Data collection is now running..."
echo ""

# Wait for collection to complete
if [ $COLLECTION_DURATION -eq 0 ]; then
    # Manual stop mode - wait indefinitely
    wait $PERF_PID
else
    # Timed mode - wait for specified duration
    elapsed=0
    interrupted=0
    while [ $elapsed -lt $COLLECTION_DURATION ]; do
        if ! kill -0 $PERF_PID 2>/dev/null; then
            # Check if process was interrupted by user (cleanup sets CLEANUP_DONE=1)
            if [ $CLEANUP_DONE -eq 1 ]; then
                # log_info "Collection stopped early at ${elapsed}s (user interrupt)"
                exit 0
            else
                log_error "Perf process terminated unexpectedly"
                cleanup
                exit 1
            fi
        fi
        sleep 1
        elapsed=$((elapsed + 1))
        
        # Progress indicator every 10 seconds
        if [ $((elapsed % 10)) -eq 0 ]; then
            log_info "Collection progress: ${elapsed}/${COLLECTION_DURATION}s"
        fi
    done
    
    log_info "Collection duration reached (${COLLECTION_DURATION}s)"
fi

# Normal completion - call cleanup explicitly
cleanup
exit 0
