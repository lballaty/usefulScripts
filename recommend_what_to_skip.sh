#!/bin/bash
#
# recommend_what_to_skip.sh
# Takes two disk reports (old + new) that include both home folder usage and /Applications usage.
# Suggests which items (folders or apps) to skip so the rest fits within new Mac's free space.
#
# Usage:
#   ./recommend_what_to_skip.sh disk_report_old_mac.txt disk_report_new_mac.txt

SOURCE_REPORT="$1"
TARGET_REPORT="$2"

if [[ -z "$SOURCE_REPORT" || -z "$TARGET_REPORT" ]]; then
  echo "Usage: $0 <disk_report_old_mac.txt> <disk_report_new_mac.txt>"
  exit 1
fi

if [[ ! -f "$SOURCE_REPORT" || ! -f "$TARGET_REPORT" ]]; then
  echo "Error: One or both report files do not exist."
  exit 1
fi

python3 <<EOF
import re

source_file = r"""${SOURCE_REPORT}"""
target_file = r"""${TARGET_REPORT}"""

def parse_size(size_str):
    s = size_str.strip().upper()
    # Typical patterns: 5.3G, 220Mi, 10K, etc.
    match = re.match(r'([0-9.]+)([GMKTI])', s)
    if match:
        val, unit = match.groups()
        val = float(val)
        if unit == 'K':
            return int(val * 1024)
        elif unit == 'M':
            return int(val * (1024**2))
        elif unit == 'G':
            return int(val * (1024**3))
        elif unit == 'T':
            return int(val * (1024**4))
        elif unit == 'I':  # e.g. Gi
            # approximate as G
            return int(val * (1024**3))
    # fallback tries ###Gi
    match2 = re.match(r'([0-9.]+)GI', s)
    if match2:
        val = float(match2.group(1))
        return int(val * (1024**3))
    return 0

def extract_free_space(lines):
    # read "df -h /" part to find Avail
    capture_next = False
    for i, line in enumerate(lines):
        if "Filesystem" in line and "Avail" in line:
            if i+1 < len(lines):
                parts = lines[i+1].split()
                if len(parts) >= 4:
                    return parse_size(parts[3])
    return 0

def extract_home_top_level(lines):
    """
    Collect lines from the section:
       '📁 Disk usage in $HOME (top-level):'
    Format: "4.0K /Users/you/Documents"
    Return dict: { '/Users/you/Documents': <bytes> }
    """
    result = {}
    in_section = False
    for line in lines:
        if "Disk usage in $HOME (top-level):" in line:
            in_section = True
            continue
        if in_section:
            if not line.strip():
                break
            if line.startswith("📁"):
                break
            tokens = line.split(maxsplit=2)
            if len(tokens) >= 2:
                size_str = tokens[0]
                path_str = tokens[1]
                size_bytes = parse_size(size_str)
                result[path_str] = size_bytes
    return result

def extract_apps(lines):
    """
    Collect lines from the section:
       '💻 Top 20 largest .app bundles in /Applications'
    Format: "5.2G /Applications/Xcode.app"
    Return dict: { '/Applications/Xcode.app': <bytes> }
    """
    result = {}
    in_section = False
    for line in lines:
        if "largest .app bundles in /Applications" in line:
            in_section = True
            continue
        if in_section:
            if not line.strip():
                break  # blank line => end of listing
            if line.startswith("✅") or line.startswith("No /Applications"):
                break
            tokens = line.split(maxsplit=2)
            if len(tokens) >= 2:
                size_str = tokens[0]
                path_str = tokens[1]
                size_bytes = parse_size(size_str)
                result[path_str] = size_bytes
    return result

def load_report(path):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    free_space = extract_free_space(lines)
    home_map = extract_home_top_level(lines)
    apps_map = extract_apps(lines)
    return free_space, home_map, apps_map

# Parse old Mac
with open(source_file, 'r') as f:
    old_lines = f.readlines()
old_free_space, old_home_map, old_apps_map = load_report(source_file)

# Parse new Mac
with open(target_file, 'r') as f:
    new_lines = f.readlines()
new_free_space, new_home_map, new_apps_map = load_report(target_file)

# Combine usage from old Mac
combined_usage_map = {}
combined_usage_map.update(old_home_map)
combined_usage_map.update(old_apps_map)

total_usage = sum(combined_usage_map.values())
new_free_gb = round(new_free_space/(1024**3), 2)

print("===== DISK FIT CHECK (Home + Apps) =====")
print(f"Old Mac total usage (home + top 20 apps) = ~{round(total_usage/(1024**3),2)} GB")
print(f"New Mac free space = ~{new_free_gb} GB")

if total_usage <= new_free_space:
    print("✅ Everything fits on the new Mac with space to spare.")
else:
    print("⚠️ Not enough space if you copy everything from old Mac.")
    print("🔎 Suggesting largest items (folders/apps) to skip...")

    # Sort items from largest to smallest
    sorted_items = sorted(combined_usage_map.items(), key=lambda x: x[1], reverse=True)
    skip_list = []
    current_total = total_usage
    for path, sz in sorted_items:
        if current_total <= new_free_space:
            break
        skip_list.append((path, sz))
        current_total -= sz

    new_total_gb = round(current_total/(1024**3), 2)
    print(f"After skipping {len(skip_list)} item(s), usage is ~{new_total_gb} GB.")
    if current_total <= new_free_space:
        print(f"✅ That now fits within the new Mac's ~{new_free_gb} GB free space.")
    else:
        print(f"⚠️ Still above new Mac free space; you may need to skip more or store data externally.")

    if skip_list:
        print("")
        print("===== RECOMMENDED SKIP LIST (largest first) =====")
        for path, sz in skip_list:
            sz_gb = round(sz/(1024**3), 2)
            print(f"- {path} ~{sz_gb} GB")
    else:
        print("No skip list recommended or not enough data found to reduce usage.")
EOF

