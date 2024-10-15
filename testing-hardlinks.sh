#!/usr/bin/env bash

# exit script on error
set -e
# exit on undeclared variable
set -u

# file used to track processed files
rebalance_db_file_name="rebalance_db.txt"

# index used for progress
current_index=0

## Color Constants

# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Cyan='\033[0;36m'         # Cyan

## Functions

# print a help message
function print_usage() {
  echo "Usage: zfs-inplace-rebalancing --checksum true --passes 1 /data/source /data/dest"
}

# print a given text entirely in a given color
function color_echo () {
    color=$1
    text=$2
    echo -e "${color}${text}${Color_Off}"
}


function get_rebalance_count () {
    file_path=$1

    line_nr=$(grep -xF -n "${file_path}" "./${rebalance_db_file_name}" | head -n 1 | cut -d: -f1)
    if [ -z "${line_nr}" ]; then
        echo "0"
        return
    else
        rebalance_count_line_nr="$((line_nr + 1))"
        rebalance_count=$(awk "NR == ${rebalance_count_line_nr}" "./${rebalance_db_file_name}")
        echo "${rebalance_count}"
        return
    fi
}

# rebalance a specific file
function rebalance () {
    file_path=$1
    hardlink_dir=$2
    hardlink_count=$(stat -c "%h" "${file_path}")
    
    echo "File path: $file_path"

    # Find other hardlinked file and remove it
    inode_val=$(ls -i "$file_path" | awk '{print $1}')
    hardlink_path=$(find "$hardlink_dir" -inum $inode_val)

    echo "inode Value: $inode_val"
    echo "Hardlinked File: $hardlink_path"
}

checksum_flag='true'
passes_flag='1'

if [[ "$#" -ne 2 ]]; then
    print_usage
    exit 0
fi

while true ; do
    case "$1" in
        -h | --help )
            print_usage
            exit 0
        ;;
        -c | --checksum )
            if [[ "$2" == 1 || "$2" =~ (on|true|yes) ]]; then
                checksum_flag="true"
            else
                checksum_flag="false"
            fi
            shift 2
        ;;
        -p | --passes )
            passes_flag=$2
            shift 2
        ;;
        *)
            break
        ;;
    esac 
done;

source_path=$1
dest_path=$2

color_echo "$Cyan" "Start rebalancing $(date):"
color_echo "$Cyan" "  Rebalance Path: ${source_path}"
color_echo "$Cyan" "  Hardlink Path: ${dest_path}"
color_echo "$Cyan" "  Rebalancing Passes: ${passes_flag}"
color_echo "$Cyan" "  Use Checksum: ${checksum_flag}"

# count number of hardlinked files
file_count=$(find "${source_path}" -type f -links 2 | wc -l)

color_echo "$Cyan" "  File count: ${file_count}"

# create db file
if [ "${passes_flag}" -ge 1 ]; then
    touch "./${rebalance_db_file_name}"
fi

# recursively scan through files and execute "rebalance" procedure if the file is a hardlink
find "$source_path" -type f -links 2 -print0 | while IFS= read -r -d '' file; do rebalance "$file" "$dest_path"; done

echo ""
echo ""
color_echo "$Green" "Done!"
