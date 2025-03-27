#!/bin/bash
#
# compare_reports.sh
# Compare two disk_report_<hostname>.txt files and produce a difference report.
#
# Usage:
#   ./compare_reports.sh /path/to/disk_report_source.txt /path/to/disk_report_target.txt

SOURCE_REPORT="$1"
TARGET_REPORT="$2"

if [[ -z "$SOURCE_REPORT" || -z "$TARGET_REPORT" ]]; then
  echo "Usage: $0 <source_report.txt> <target_report.txt>"
  exit 1
fi

if [[ ! -f "$SOURCE_REPORT" || ! -f "$TARGET_REPORT" ]]; then
  echo "Error: One or both report files do not exist."
  exit 1
fi

#############################################
# Embedded Python for robust text parsing
#############################################
python3 <<EOF
import re
import sys
import os

source_file = r"""${SOURCE_REPORT}"""
target_file = r"""${TARGET_REPORT}"""

def parse_df_h(lines):
    """
    Parse 'df -h /' line to get available disk space.
    Returns available space in bytes (approx) or None.
    """
    # Typical line: "Filesystem   Size   Used  Avail Capacity Mounted on"
    # Next line might be: "/dev/disk1s5  465Gi  23Gi  442Gi   5%       /"
    # We'll look for a line with Avail in it, parse the next line's 4th column
    # This is a bit fragile if local is changed, but works for standard English df output
    capture = False
    for i, line in enumerate(lines):
        if "Filesystem" in line and "Avail" in line:
            # next line should have actual usage
            if i+1 < len(lines):
                columns = lines[i+1].split()
                if len(columns) >= 4:
                    avail_str = columns[3]
                    return parse_size(avail_str)
    return None

def parse_size(size_str):
    """
    Convert e.g. '442Gi' or '1.3G' or '512K' to bytes (approx).
    """
    size_str = size_str.strip().upper()
    match = re.match(r"([0-9.]+)([GMKTI])", size_str)
    if not match:
        # fallback: sometimes '444Gi'
        match2 = re.match(r"([0-9.]+)GI", size_str)
        if match2:
            val = float(match2.group(1))
            return int(val * (1024**3))
        # unknown format or can't parse, return 0
        return 0
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
    elif unit == 'I':  # e.g. "Gi"
        # let's guess it's G? This is a fallback.
        return int(val * (1024**3))
    return 0

def parse_du_top(lines, section_header="Disk usage in $HOME (top-level):"):
    """
    Parse lines after the heading "📁 Disk usage in $HOME (top-level):"
    until a blank line or next heading.
    Return dict: { folderName: sizeInBytes }
    """
    usage_map = {}
    collecting = False
    for line in lines:
        # Start collecting lines after we see the section_header
        if section_header in line:
            collecting = True
            continue

        if collecting:
            # stop if empty line or next "📁" heading
            if not line.strip():
                break
            if line.startswith("📁"):
                # new heading
                break
            # lines typically look like "4.0K /Users/me/Desktop"
            # We'll parse the first token as size, second as path
            tokens = line.split(maxsplit=2)
            if len(tokens) >= 2:
                size_str = tokens[0]
                # path = tokens[1] might have spaces
                path = tokens[1]
                usage_map[path] = parse_size(size_str)
    return usage_map

def parse_subfolders(lines):
    """
    Parse the lines after:
      "📁 Top 10 largest directories within ~/Documents, ~/Downloads, ..."
    Return a dict of { folderPath: sizeInBytes }
    We'll store them all in one dictionary, with the full path as key.
    """
    sub_map = {}
    collecting = False
    for i, line in enumerate(lines):
        if "Top 10 largest directories within" in line:
            collecting = True
            continue
        if collecting:
            # stop if we reach end or next heading "✅"
            if line.startswith("✅"):
                break

            # We might see lines like:
            # "🔹 Documents:"
            # "12G    /Users/me/Documents/VideoProject"
            # ...
            if line.startswith("🔹"):
                # skipping heading line
                continue
            if not line.strip():
                # blank line = next block
                continue

            tokens = line.split(maxsplit=2)
            if len(tokens) >= 2:
                size_str = tokens[0]
                path = tokens[1]
                sub_map[path] = parse_size(size_str)

    return sub_map

def read_report(path):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        lines = f.readlines()
    # parse free space
    free_bytes = parse_df_h(lines)
    top_map = parse_du_top(lines)
    sub_map = parse_subfolders(lines)
    return free_bytes, top_map, sub_map

source_free, source_top, source_sub = read_report(source_file)
target_free, target_top, target_sub = read_report(target_file)

print("========== DISK REPORT COMPARISON ==========")
print(f"Source file: {os.path.basename(source_file)}")
print(f"Target file: {os.path.basename(target_file)}")
print("")

if source_free is not None and target_free is not None:
    sf_gb = round(source_free/(1024**3), 2)
    tf_gb = round(target_free/(1024**3), 2)
    print(f"📍 Source FREE space: {sf_gb} GB approx")
    print(f"📍 Target FREE space: {tf_gb} GB approx")
    if sf_gb > tf_gb:
        print("⚠️ Target has LESS free space than source.")
    else:
        print("✅ Target has more or equal free space than source (good sign).")
    print("")
else:
    print("⚠️ Could not parse free space from one or both reports.\n")

##########################
# Compare top-level usage
##########################

print("===== TOP-LEVEL USAGE COMPARISON (~/) =====")
all_keys = set(source_top.keys()) | set(target_top.keys())
for path in sorted(all_keys):
    s_size = source_top.get(path, 0)
    t_size = target_top.get(path, 0)
    if s_size > 0 or t_size > 0:
        s_gb = round(s_size/(1024**3), 2)
        t_gb = round(t_size/(1024**3), 2)
        print(f"{path:60s} | Source: {s_gb} GB | Target: {t_gb} GB")

print("")

##########################
# Compare subfolder usage
##########################
print("===== SUBFOLDER USAGE COMPARISON (Documents, Downloads, etc.) =====")
all_sub_keys = set(source_sub.keys()) | set(target_sub.keys())
for path in sorted(all_sub_keys):
    s_size = source_sub.get(path, 0)
    t_size = target_sub.get(path, 0)
    if s_size > 0 or t_size > 0:
        s_gb = round(s_size/(1024**3), 2)
        t_gb = round(t_size/(1024**3), 2)
        diff = s_gb - t_gb
        print(f"{path:60s} | Source: {s_gb} GB | Target: {t_gb} GB | Diff: {diff} GB")

print("")
print("===== SUGGESTIONS =====")
print("- Look for large folders on Source that don't exist or are smaller on Target.")
print("- If Target free space is significantly smaller than total large folders on Source, consider NOT migrating them.")
print("- For more fine-grained file-level analysis, use 'du -sh' or a tool like GrandPerspective.")
print("============================================")
EOF

