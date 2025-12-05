# g#collect

Hardware Performance and Usage Data Collection utility.

## Overview

g#collect is a bash-based tool for collecting comprehensive hardware performance data. It captures CPU performance metrics, system configuration, and hardware utilization data using Linux perf and system monitoring tools.

## Requirements

- Root privileges (or `CAP_SYS_ADMIN` + `CAP_PERFMON` capabilities)
- `perf` tool (install via `linux-tools-common` and `linux-tools-$(uname -r)`)
- `lscpu` (optional, for CPU info - util-linux package)
- `turbostat` (optional, for power/frequency data)
- `curl` (optional, for auto-upload feature)
- Sufficient disk space (perf data files can reach 100s of MB)

## Installation

1. Clone or download this repository
2. Make the script executable:
```bash
chmod +x g#collect.sh
```

## Usage

### Quick Start

```bash
# Basic collection with label (manual stop with Ctrl+C)
sudo ./g#collect.sh -l my_test

# Timed 60-second collection
sudo ./g#collect.sh -l peak_load -d 60

# Collect from specific cores
sudo ./g#collect.sh -l worker_cores -c "1-30,33-62" -d 120
```

### Workflow

1. **Start collection** before starting your test:
```bash
sudo ./g#collect.sh -l my_5g_test
```

2. **Run your test** after seeing "Data collection is now running..."

3. **Stop collection**:
   - For manual mode (default): Press `Ctrl+C` when test completes
   - For timed mode: Collection stops automatically after specified duration

4. **Transfer the output bundle** (`<hostname>_<label>_gcollect_YYYYMMDD_HHMMSS.tar.gz` file) for analysis

### Command-Line Options

```
Usage: sudo ./g#collect.sh [OPTIONS]

Collection Settings:
  -e, --events EVENTS     Perf events to record (comma-separated)
  -d, --duration SECS     Collection duration in seconds (0 = manual stop, default)
  -l, --label LABEL       Label for output filenames (recommended)
  -o, --output DIR        Output directory (default: current directory)

Core Selection:
  -c, --cores CORES       Manually specify cores (e.g., "1-30,33-62")
  -a, --all-cores         Monitor all cores (system-wide)
  --auto                  Auto-detect isolated cores (default)

Additional Options:
  --perf-opts OPTS        Extra perf record options (default: "-T")
  --turbostat             Include turbostat output (default)
  --no-turbostat          Skip turbostat collection
  --turbostat-iter N      Turbostat iterations (default: 5)
  --bundle                Create tar.gz bundle (default)
  --no-bundle             Keep individual files instead of bundle
  --symbols               Create symbol archive for offline analysis
  --no-symbols            Don't create symbol archive (default)

Auto-Upload:
  --upload                Enable auto-upload after collection
  --upload-url URL        Upload server URL
  --upload-token TOKEN    Upload authentication token
  --upload-timeout SECS   Upload timeout in seconds (default: 300)

Other:
  -h, --help              Show help message
  -v, --version           Show version
```

### Examples

```bash
# Custom events
sudo ./g#collect.sh -l cache_test -e "cycles,cache-misses,LLC-load-misses"

# System-wide collection for 60 seconds
sudo ./g#collect.sh -l full_system -a -d 60

# Collection with auto-upload
sudo ./g#collect.sh -l production -d 300 --upload --upload-url http://myserver/upload --upload-token mytoken

# Skip turbostat, keep individual files
sudo ./g#collect.sh -l quick_test --no-turbostat --no-bundle
```

## Troubleshooting

**"This script must be run as root"**
- Run with `sudo` or as root user

**"perf tool not found"**
- Install: `linux-tools-common linux-tools-$(uname -r)`

**Large output files**
- Adjust sampling periods in events (increase period values)
- Reduce collection duration with `-d`
- Use core-specific collection with `-c` instead of system-wide

**"No isolated cores found"**
- Script will fall back to system-wide collection
- To isolate cores, add `isolcpus=` to kernel boot parameters

## License

This software is provided under a Trial License by Cirrus360 Corp. See the [LICENSE](LICENSE) file for complete terms and conditions.

For licensing inquiries, contact Cirrus360 Corp.

## Copyright

Copyright (c) 2025 Cirrus360 Corp. All Rights Reserved.

Contains Cirrus360 CONFIDENTIAL AND PROPRIETARY INFORMATION. Subject to Non-Disclosure Agreement (NDA).
