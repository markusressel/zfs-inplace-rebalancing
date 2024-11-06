#!/usr/bin/env bash

# Exit script on error
set -e
# Exit on undeclared variable
set -u

# File used to track processed files
rebalance_db_file_name="rebalance_db.txt"

# Index used for progress
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

# Print a help message
function print_usage() {
  echo "Usage: zfs-inplace-rebalancing.sh --checksum true --passes 1 --debug true /my/pool"
}

# Print a given text entirely in a given color
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

# Rebalance a group of files that are hardlinked together
function process_inode_group() {
    paths=("$@")
    num_paths="${#paths[@]}"

    # Progress tracking
    current_index="$((current_index + 1))"
    progress_raw=$((current_index * 10000 / file_count))
    progress_percent=$(printf '%0.2f' "${progress_raw}e-2")
    color_echo "${Cyan}" "Progress -- Files: ${current_index}/${file_count} (${progress_percent}%)"

    if [ "$debug_flag" = true ]; then
        echo "Processing inode group with ${num_paths} paths:"
        for path in "${paths[@]}"; do
            echo " - $path"
        done
    fi

    # Check rebalance counts for all files
    should_skip=false
    for path in "${paths[@]}"; do
        rebalance_count=$(get_rebalance_count "${path}")
        if [ "${rebalance_count}" -ge "${passes_flag}" ]; then
            should_skip=true
            break
        fi
    done

    if [ "${should_skip}" = true ]; then
        if [ "${num_paths}" -gt 1 ]; then
            color_echo "${Yellow}" "Rebalance count (${passes_flag}) reached, skipping group: ${paths[*]}"
        else
            color_echo "${Yellow}" "Rebalance count (${passes_flag}) reached, skipping: ${paths[0]}"
        fi
        return
    fi

    main_file="${paths[0]}"

    # Check if main_file exists
    if [[ ! -f "${main_file}" ]]; then
        color_echo "${Yellow}" "File is missing, skipping: ${main_file}"
        return
    fi

    tmp_extension=".balance"
    tmp_file_path="${main_file}${tmp_extension}"

    echo "Copying '${main_file}' to '${tmp_file_path}'..."
    if [ "$debug_flag" = true ]; then
        echo "Executing copy command:"
    fi
    if [[ "${OSTYPE,,}" == "linux-gnu"* ]]; then
        # Linux
        cmd=(cp --reflink=never -ax "${main_file}" "${tmp_file_path}")
        if [ "$debug_flag" = true ]; then
            echo "${cmd[@]}"
        fi
        "${cmd[@]}"
    elif [[ "${OSTYPE,,}" == "darwin"* ]] || [[ "${OSTYPE,,}" == "freebsd"* ]]; then
        # Mac OS and FreeBSD
        cmd=(cp -ax "${main_file}" "${tmp_file_path}")
        if [ "$debug_flag" = true ]; then
            echo "${cmd[@]}"
        fi
        "${cmd[@]}"
    else
        echo "Unsupported OS type: $OSTYPE"
        exit 1
    fi

    # Compare copy against original to make sure nothing went wrong
    if [[ "${checksum_flag,,}" == "true"* ]]; then
        echo "Comparing copy against original..."
        if [[ "${OSTYPE,,}" == "linux-gnu"* ]]; then
            # Linux
            original_md5=$(md5sum -b "${main_file}" | awk '{print $1}')
            copy_md5=$(md5sum -b "${tmp_file_path}" | awk '{print $1}')
        elif [[ "${OSTYPE,,}" == "darwin"* ]] || [[ "${OSTYPE,,}" == "freebsd"* ]]; then
            # Mac OS and FreeBSD
            original_md5=$(md5 -q "${main_file}")
            copy_md5=$(md5 -q "${tmp_file_path}")
        else
            echo "Unsupported OS type: $OSTYPE"
            exit 1
        fi

        if [ "$debug_flag" = true ]; then
            echo "Original MD5: $original_md5"
            echo "Copy MD5: $copy_md5"
        fi

        if [[ "${original_md5}" == "${copy_md5}" ]]; then
            color_echo "${Green}" "MD5 OK"
        else
            color_echo "${Red}" "MD5 FAILED: ${original_md5} != ${copy_md5}"
            exit 1
        fi
    fi

    echo "Removing original files..."
    for path in "${paths[@]}"; do
        if [ "$debug_flag" = true ]; then
            echo "Removing $path"
        fi
        rm "${path}"
    done

    echo "Renaming temporary copy to original '${main_file}'..."
    if [ "$debug_flag" = true ]; then
        echo "Moving ${tmp_file_path} to ${main_file}"
    fi
    mv "${tmp_file_path}" "${main_file}"

    echo "Recreating hardlinks..."
    for (( i=1; i<${#paths[@]}; i++ )); do
        if [ "$debug_flag" = true ]; then
            echo "Linking ${main_file} to ${paths[$i]}"
        fi
        ln "${main_file}" "${paths[$i]}"
    done

    if [ "${passes_flag}" -ge 1 ]; then
        # Update rebalance "database" for all files
        for path in "${paths[@]}"; do
            line_nr=$(grep -xF -n "${path}" "./${rebalance_db_file_name}" | head -n 1 | cut -d: -f1)
            if [ -z "${line_nr}" ]; then
                rebalance_count=1
                echo "${path}" >> "./${rebalance_db_file_name}"
                echo "${rebalance_count}" >> "./${rebalance_db_file_name}"
            else
                rebalance_count_line_nr="$((line_nr + 1))"
                rebalance_count=$(awk "NR == ${rebalance_count_line_nr}" "./${rebalance_db_file_name}")
                rebalance_count="$((rebalance_count + 1))"
                if [ "$debug_flag" = true ]; then
                    echo "Updating rebalance count for ${path} to ${rebalance_count}"
                fi
                sed -i "${rebalance_count_line_nr}s/.*/${rebalance_count}/" "./${rebalance_db_file_name}"
            fi
        done
    fi
}

checksum_flag='true'
passes_flag='1'
debug_flag='false'

if [[ "$#" -eq 0 ]]; then
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
        --debug )
            if [[ "$2" == 1 || "$2" =~ (on|true|yes) ]]; then
                debug_flag="true"
            else
                debug_flag="false"
            fi
            shift 2
        ;;
        *)
            break
        ;;
    esac 
done;

root_path=$1

color_echo "$Cyan" "Start rebalancing $(date):"
color_echo "$Cyan" "  Path: ${root_path}"
color_echo "$Cyan" "  Rebalancing Passes: ${passes_flag}"
color_echo "$Cyan" "  Use Checksum: ${checksum_flag}"
color_echo "$Cyan" "  Debug Mode: ${debug_flag}"

# Generate files_list.txt with device and inode numbers using stat, separated by a pipe '|'
if [[ "${OSTYPE,,}" == "linux-gnu"* ]]; then
    # Linux
    find "$root_path" -type f -not -path '*/.zfs/*' -exec stat --printf '%d:%i|%n\n' {} \; > files_list.txt
elif [[ "${OSTYPE,,}" == "darwin"* ]] || [[ "${OSTYPE,,}" == "freebsd"* ]]; then
    # Mac OS and FreeBSD
    find "$root_path" -type f -not -path '*/.zfs/*' -exec sh -c 'stat -f "%d:%i|%N" "$0"' {} \; {} \; > files_list.txt
else
    echo "Unsupported OS type: $OSTYPE"
    exit 1
fi

if [ "$debug_flag" = true ]; then
    echo "Contents of files_list.txt:"
    cat files_list.txt
fi

# Sort files_list.txt by device and inode number
sort -t '|' -k1,1 files_list.txt > sorted_files_list.txt

if [ "$debug_flag" = true ]; then
    echo "Contents of sorted_files_list.txt:"
    cat sorted_files_list.txt
fi

# Use awk to group paths by inode key
awk -F'|' '{
    key = $1
    path = $2
    if (key == prev_key) {
        paths = paths " " path
    } else {
        if (NR > 1) {
            print prev_key "|" paths
        }
        prev_key = key
        paths = path
    }
}
END {
    if (NR > 0) {
        print prev_key "|" paths
    }
}' sorted_files_list.txt > grouped_inodes.txt

if [ "$debug_flag" = true ]; then
    echo "Contents of grouped_inodes.txt:"
    cat grouped_inodes.txt
fi

# Count number of inode groups
file_count=$(wc -l < grouped_inodes.txt | tr -d ' ')

color_echo "$Cyan" "  Number of files to process: ${file_count}"

# Initialize current_index
current_index=0

# Create db file
if [ "${passes_flag}" -ge 1 ]; then
    touch "./${rebalance_db_file_name}"
fi

# Read grouped_inodes.txt and process each group
while IFS='|' read -r key paths; do
    if [ "$debug_flag" = true ]; then
        echo "Detected inode group: key=${key}"
        echo "Paths:${paths}"
    fi
    # Split the paths into an array
    read -a path_array <<< "${paths}"
    process_inode_group "${path_array[@]}"
done < grouped_inodes.txt

# Clean up temporary files
rm files_list.txt sorted_files_list.txt grouped_inodes.txt

echo ""
echo ""
color_echo "$Green" "Done!"
