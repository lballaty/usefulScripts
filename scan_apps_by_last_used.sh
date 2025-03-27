#!/bin/bash
#
# scan_apps_by_last_used.sh
# Lists each .app in /Applications, shows:
#   - Size on disk
#   - Last used date (if known via Spotlight)
#   - Days since last use
# Then sorts the list so the oldest used apps appear first (largest "days since use").
#
# Usage:
#   chmod +x scan_apps_by_last_used.sh
#   ./scan_apps_by_last_used.sh
#
# Output is printed to the terminal in CSV-like format.

# Note: For accuracy, macOS needs Spotlight indexing to be active.
# If you see many "null" for last-used dates, those apps may never have been launched
# or don't have usage metadata. That often indicates "safe to skip" if they're large.

echo "🔎 Scanning /Applications for size & last-used date..."

python3 <<EOF
import os
import re
import subprocess
import datetime

apps_dir = "/Applications"

if not os.path.isdir(apps_dir):
    print(f"No /Applications directory found at {apps_dir}")
    exit(0)

# We'll collect data in a list of dicts:
# [ { 'name': str, 'path': str, 'size': '5.3G', 'size_bytes': int, 'last_used': datetime, 'days_since_use': int }, ... ]

app_info_list = []

def parse_size(size_str):
    # Convert strings like "5.3G", "220Mi", "512K" to approximate bytes
    # We'll handle 'K', 'M', 'G', 'T' plus 'Gi'
    size_str = size_str.strip().upper()
    # Typical patterns: 5.3G, 220Mi, 10K, etc.
    match = re.match(r'([0-9.]+)([GMKTI])', size_str)
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
        elif unit == 'I':  # 'Gi'
            return int(val * (1024**3))
    # fallback tries ###Gi
    match2 = re.match(r'([0-9.]+)GI', size_str)
    if match2:
        val = float(match2.group(1))
        return int(val * (1024**3))
    return 0

def get_app_size(app_path):
    # Use 'du -sh' to get human-readable size
    try:
        du_output = subprocess.check_output(["du", "-sh", app_path], stderr=subprocess.DEVNULL)
        size_str = du_output.decode('utf-8', 'ignore').split()[0]
        return size_str
    except:
        return "0K"

def get_last_used_date(app_path):
    # Use 'mdls -name kMDItemLastUsedDate -raw'
    # If the app has never been used or there's no metadata, mdls returns (null).
    try:
        mdls_output = subprocess.check_output([
            "mdls", "-name", "kMDItemLastUsedDate", "-raw", app_path
        ], stderr=subprocess.DEVNULL).decode('utf-8', 'ignore').strip()
        if mdls_output == "(null)" or not mdls_output:
            return None
        # Typically: "2021-05-10 12:00:00 +0000"
        # We'll parse with strptime ignoring the timezone offset
        # or parse manually if needed
        # Let's split on the '+' which might not always exist
        date_part = mdls_output.split('+')[0].strip()
        # date_part like "2021-05-10 12:00:00"
        dt = datetime.datetime.strptime(date_part, "%Y-%m-%d %H:%M:%S")
        return dt
    except:
        return None

now = datetime.datetime.now()

# Iterate over all .app bundles in /Applications
for item in sorted(os.listdir(apps_dir)):
    if not item.endswith(".app"):
        continue
    full_path = os.path.join(apps_dir, item)
    # 1) get size
    human_size = get_app_size(full_path)
    size_bytes = parse_size(human_size)
    # 2) get last used date
    last_used_dt = get_last_used_date(full_path)
    if last_used_dt:
        days_since_use = (now - last_used_dt).days
    else:
        days_since_use = None
    
    app_info_list.append({
        "name": item,
        "path": full_path,
        "size": human_size,
        "size_bytes": size_bytes,
        "last_used_dt": last_used_dt,
        "days_since_use": days_since_use
    })

# Sort by days since use descending (so oldest used is top).
# If an app has never been used (days_since_use is None), put it at the top.
def sort_key(app):
    # Return (days_since_use or large number, size_bytes descending maybe?)
    # We'll primarily sort by days_since_use descending,
    # secondarily by size descending if you want:
    ds = app["days_since_use"]
    if ds is None:
        # treat None as extremely large => very old
        ds = 999999
    return (ds, app["size_bytes"])

app_info_list.sort(key=sort_key, reverse=True)

print("App Name,Size on Disk,Days Since Last Use,Last Used Date,App Path")
for info in app_info_list:
    ds = info["days_since_use"]
    ds_str = str(ds) if ds is not None else "Never used / No data"
    dt_str = info["last_used_dt"].strftime("%Y-%m-%d") if info["last_used_dt"] else "N/A"
    print(f"{info['name']},{info['size']},{ds_str},{dt_str},{info['path']}")
EOF

echo "✅ Done. Above is a CSV-like table. Copy/paste or redirect to a file to keep it."

