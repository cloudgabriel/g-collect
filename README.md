# g#collect

Hardware Performance and Usage Data Collection utility.

## Overview

g#collect is a bash-based tool for collecting comprehensive hardware performance data. It captures CPU performance metrics, system configuration, and hardware utilization data using Linux perf and system monitoring tools.

## Requirements

- Root privileges (or `CAP_SYS_ADMIN` + `CAP_PERFMON` capabilities)
- `perf` tool (install via `linux-tools-common` and `linux-tools-$(uname -r)`)
- `lscpu` (util-linux package)
- `turbostat` (optional, for power/frequency data)
- Sufficient disk space (perf data files can reach 100s of MB)

## Installation

1. Clone or download this repository
2. Make the script executable:
```bash
   chmod +x g#collect.sh
```

## Usage

### Default Workflow

1. **Configure the script** by editing variables at the top of `g#collect.sh`:
```bash
   TEST_LABEL="my_5g_test"           # Label for output files
```

2. **Start collection** (before starting your test):
```bash
   sudo ./g#collect.sh
```

3. **Run your test** after seeing "Data collection is now running..."

4. **Stop collection**:
   - For manual mode: Press `Ctrl+C` when test completes

5. **Transfer the output bundle** (`.tar.gz` file) for analysis

### Configuration Options

These variables can be edited in the script before running:

| Variable | Description | Default |
|----------|-------------|---------|
| `PERF_EVENTS` | Comma-separated list of perf events to record | cycles/period=100000/,instructions/period=100000/,L1-dcache-load-misses/period=10000/,LLC-load-misses/period=10000/ |
| `COLLECTION_DURATION` | Collection time in seconds (0 = manual stop) | 0 |
| `TEST_LABEL` | Label added to output filenames | "" |
| `OUTPUT_DIR` | Directory for output files | "." |
| `CORE_MODE` | "auto" (detect isolated cores) or "manual" | "auto" |
| `MANUAL_CORES` | Core specification if CORE_MODE="manual" | "" |
| `INCLUDE_TURBOSTAT` | Include turbostat output (yes/no) | "yes" |
| `CREATE_BUNDLE` | Create compressed bundle of outputs (yes/no) | "yes" |
| `CREATE_SYMBOL_ARCHIVE` | Create perf symbol archive (yes/no) | "no" |

## Troubleshooting

**"This script must be run as root"**
- Run with `sudo` or as root user

**"perf tool not found"**
- Install: `sudo apt-get install linux-tools-common linux-tools-$(uname -r)`

**Large output files**
- Adjust sampling periods in `PERF_EVENTS` (increase period values)
- Reduce `COLLECTION_DURATION`
- Use core-specific collection instead of system-wide

**"No isolated cores found"**
- Script will fall back to system-wide collection
- To isolate cores, add `isolcpus=` to kernel boot parameters

## License

This software is provided under a Trial License by Cirrus360 Corp. See the [LICENSE](LICENSE) file for complete terms and conditions.

For licensing inquiries, contact Cirrus360 Corp.

## Copyright

Copyright (c) 2025 Cirrus360 Corp. All Rights Reserved.

Contains Cirrus360 CONFIDENTIAL AND PROPRIETARY INFORMATION. Subject to Non-Disclosure Agreement (NDA).
