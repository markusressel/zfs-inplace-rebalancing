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
Color_Off='\033[0m' # Text Reset

# Regular Colors
Red='\033[0;31m'    # Red
Green='\033[0;32m'  # Green
Yellow='\033[0;33m' # Yellow
Cyan='\033[0;36m'   # Cyan

## Functions

# Print a help message
function print_usage() {
    echo "Usage: zfs-inplace-rebalancing.sh --checksum true --passes 1 --debug false --test false /my/pool"
}

# Print a given text entirely in a given color
function color_echo() {
    local color=$1
    shift
    local text="$*"
    echo -e "${color}${text}${Color_Off}"
}

# Print a given text entirely in a given color
function echo_debug() {
    if [ "$debug_flag" = true ]; then
        text=$*
        echo "${text}"
    fi
}

# Initialize flat database arrays (Kept for compatibility, unused in basic sh)
db_paths=()
db_counts=()
db_size=0

# Cleaned up database loader for environments missing associative arrays
function load_rebalance_db_to_memory() {
    if [ -f "./${rebalance_db_file_name}" ]; then
        echo "Using direct file-lookups for database tracking..."
    fi
}

# Flat-file sequential lookup function safely handling complex strings
function get_rebalance_count() {
    local file_path="$1"
    if [ -f "./${rebalance_db_file_name}" ]; then
        # Search the database file safely for an exact path match and pull the line directly below it
        local match_count
        match_count=$(grep -F -A 1 "$file_path" "./${rebalance_db_file_name}" | tail -n 1)
        # Verify result is a real integer string
        if [ -n "$match_count" ] && [ "$match_count" -eq "$match_count" ] 2>/dev/null; then
            echo "$match_count"
        else
            echo "0"
        fi
    else
        echo "0"
    fi
}


# Rebalance a group of files that are hardlinked together
function process_inode_group() {
    paths=("$@")
    num_paths="${#paths[@]}"

    # Progress tracking safely avoiding division by zero errors
    current_index="$((current_index + 1))"
    local safe_total=${file_count:-1}
    if [ "$safe_total" -le 0 ]; then safe_total=1; fi
    
    progress_raw=$((current_index * 10000 / safe_total))
    progress_percent=$(printf '%0.2f' "${progress_raw}e-2")
    color_echo "${Cyan}" "Progress -- Files: ${current_index}/${safe_total} (${progress_percent}%)"

    echo_debug "Processing inode group with ${num_paths} paths:"
    for path in "${paths[@]}"; do
        echo_debug " - $path"
    done

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
    #strip \n off the end on QNAP
    main_file="${main_file%\\n}"
    
    # Check if main_file exists
    if [ -f "${main_file}" ]; then
        echo_debug "Found: ${main_file}"
    else
        color_echo "${Yellow}" "File is missing, skipping: ${main_file}"
        return
    fi

    tmp_extension=".balance"
    tmp_file_path="${main_file}${tmp_extension}"

    echo "Copying '${main_file}' to '${tmp_file_path}'..."
    echo_debug "Executing copy command:"

    if [[ "${OSName}" == "linux-gnu"* ]]; then
        # Linux

        # --reflink=never -- force standard copy (see ZFS Block Cloning)
        # -a -- keep attributes, includes -d -- keep symlinks (dont copy target) and
        #       -p -- preserve ACLs to
        # -x -- stay on one system
        
		echo_debug "dd if=\"${main_file}\" bs=4M 2>/dev/null | dd of=\"${tmp_file_path}\" bs=1M 2>/dev/null"

        if [ "$test_flag" != true ]; then
		
		   if [ -e "${tmp_file_path}" ]; then
              color_echo "${Red}" "Temporary rebalance file already exists: ${tmp_file_path}"
              color_echo "${Red}" "Refusing to overwrite it."
              exit 1
           fi
		
           dd if="${main_file}" bs=2M  | dd of="${tmp_file_path}" bs=1M >/dev/null
		   
		   # Restore basic metadata
		   owner_uid=$(stat -c '%u' "${main_file}")
           owner_gid=$(stat -c '%g' "${main_file}")

           chown "${owner_uid}:${owner_gid}" "${tmp_file_path}"
		   
           file_mode=$(stat -c '%a' "${main_file}")
           chmod "${file_mode}" "${tmp_file_path}"
		   
           touch --reference="${main_file}" "${tmp_file_path}"
		   
		   # Restore ACLs
           getfacl --access "${main_file}" | setfacl --set-file=- "${tmp_file_path}"
           
           # Restore extended attributes, if present
           if getfattr --absolute-names --dump "${main_file}" 2>/dev/null | grep -q '^user\.\|^security\.\|^system\.\|^trusted\.'; then
               # Safe string replacement for pure shell runtime environments
               local safe_tmp_path
               safe_tmp_path=$(echo "${tmp_file_path}" | sed 's/&/\\&/g')
               getfattr --absolute-names --dump "${main_file}" | sed "s|^# file: .*|# file: ${safe_tmp_path}|" | setfattr --restore=-
           fi

        else
		   color_echo "${Yellow}" "${cmd[@]}"
           color_echo "${Yellow}" "Test Mode, Skipping Copy"
        fi
    elif [[ "${OSName}" == "darwin"* ]] || [[ "${OSName}" == "freebsd"* ]]; then
        # Mac OS and FreeBSD
        cmd=(cp -ax "${main_file}" "${tmp_file_path}")
        echo_debug "${cmd[@]}"
        if [ "${test_flag}" != true ]; then
           "${cmd[@]}"
        else
           color_echo "${Yellow}" "Test Mode, Skipping Copy"
        fi
    else
        echo "Unsupported OS type: $OSTYPE"
        exit 1
    fi

    # Compare copy against original to make sure nothing went wrong
    if [[ "${checksum_flag}" == "true"* ]]; then
        echo "Comparing copy against original..."
        if [[ "${OSName}" == "linux-gnu"* ]]; then
            # Linux

            # file attributes (safely extract only the first column using cut)
            original_perms=$(lsattr -d "${main_file}" | cut -d' ' -f1)
            # file permissions, owner, group, size, modification time
            original_perms="${original_perms} $(stat -c "%A %U %G %s %Y" "${main_file}")"

            # file attributes
            if [ "${test_flag}" != true ]; then
              copy_perms=$(lsattr -d "${tmp_file_path}" | cut -d' ' -f1)
              # file permissions, owner, group, size, modification time
              copy_perms="${copy_perms} $(stat -c "%A %U %G %s %Y" "${tmp_file_path}")"
            else
              copy_perms=$original_perms 
            fi            
            
        elif [[ "${OSName}" == "darwin"* ]] || [[ "${OSName}" == "freebsd"* ]]; then
            # Mac OS
            # FreeBSD
            original_perms="$(stat -f "%Sp %Su %Sg %z %m" "${main_file}")"

            if [ "${test_flag}" != true ]; then
               copy_perms="$(stat -f "%Sp %Su %Sg %z %m" "${tmp_file_path}")"
            else
               copy_perms=$original_perms
            fi
        else
            echo "Unsupported OS type: $OSTYPE"
            exit 1
        fi

        echo_debug "Original perms: $original_perms"
        echo_debug "Copy perms: $copy_perms"

        if [[ "${original_perms}" == "${copy_perms}"* ]]; then
            color_echo "${Green}" "Attribute and permission check OK"
        else
            color_echo "${Red}" "Attribute and permission check FAILED: ${original_perms} != ${copy_perms}"
            exit 1
        fi

        if [ "${test_flag}" != true ]; then
           if cmp -s "${main_file}" "${tmp_file_path}"; then
               color_echo "${Green}" "File content check OK"
           else
               color_echo "${Red}" "File content check FAILED"
               exit 1
           fi
        else
           color_echo "${Green}" "File content check OK"
        fi
    fi

    echo "Removing original files..."
    for path in "${paths[@]}"; do
        echo_debug "Removing $path"
        if [ "${test_flag}" != true ]; then
           rm "${path%\\n}"
        fi
    done

    echo "Renaming temporary copy to original '${main_file}'..."
    echo_debug "Moving ${tmp_file_path} to ${main_file}"
    if [ "${test_flag}" != true ]; then
       mv "${tmp_file_path}" "${main_file}"
    fi

    # Only recreate hardlinks if there are multiple paths
    if [ "${num_paths}" -gt 1 ]; then
        echo "Recreating hardlinks..."
        for (( i=1; i<${#paths[@]}; i++ )); do
            echo_debug "Linking ${main_file} to ${paths[$i]}"
            if [ "${test_flag}" != true ]; then
               ln "${main_file}" "${paths[$i]}"
            fi
        done
    fi

    if [ "${passes_flag}" -ge 1 ] && [ "${test_flag}" != true ]; then
        # Update rebalance "database" for all files
        for path in "${paths[@]}"; do
            # Append changes directly to the database file
            echo "${path}" >> "./${rebalance_db_file_name}"
            echo "$((passes_flag))" >> "./${rebalance_db_file_name}"
        done
    fi

}

checksum_flag='true'
passes_flag='1'
debug_flag='false'
test_flag='true'

POSITIONAL_ARGS=()

if [[ "$#" -eq 0 ]]; then
    print_usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
    -h | --help)
        print_usage
        exit 0
        ;;
    -c | --checksum)
        if [[ "$2" == 1 || "$2" =~ (on|true|yes) ]]; then
            checksum_flag="true"
        else
            checksum_flag="false"
        fi
        shift 2
        ;;
    -p | --passes)
        passes_flag=$2
        shift 2
        ;;
    --debug)
        if [[ "$2" == 1 || "$2" =~ (on|true|yes) ]]; then
            debug_flag="true"
        else
            debug_flag="false"
        fi
        shift 2
        ;;
    --test)
        if [[ "$2" == 1 || "$2" =~ (on|true|yes) ]]; then
            test_flag="true"
        else
            test_flag="false"
        fi
        shift 2
        ;;
    *)
        POSITIONAL_ARGS+=("$1") # save positional arg
        shift # past argument
        ;;
    esac
done

set -- "${POSITIONAL_ARGS[@]}" # restore positional parameters


OSName=$(echo "$OSTYPE" | tr '[:upper:]' '[:lower:]')

color_echo "$Cyan" "Start rebalancing $(date):"
color_echo "$Cyan" "  Rebalancing Passes: ${passes_flag}"
color_echo "$Cyan" "  Use Checksum: ${checksum_flag}"
color_echo "$Cyan" "  Debug Mode: ${debug_flag}"
color_echo "$Cyan" "  Test Mode: ${test_flag}"
echo -e "\n"

# Generate files_list.txt with device and inode numbers using stat, separated by a pipe '|'
if [[ "${OSName}" == "linux-gnu"* ]] || [[ "${OSName}" == "darwin"* ]] || [[ "${OSName}" == "freebsd"* ]]; then
    rm -f files_list.txt
	
	# String tracker to keep tabs on paths we already looked at
    processed_paths=""

    for i in "$@"; do
       root_path=${i}
       
       # Check if this exact path string is already in our tracker
       if [[ " $processed_paths " == *" $root_path "* ]]; then
           color_echo "$Yellow" "Warning: Duplicate path detected and skipped -> ${root_path}"
           shift
           continue
       fi

       # Add the current path to our tracking string
       processed_paths="${processed_paths} ${root_path}"

       color_echo "$Cyan" " Path: ${root_path}"
       echo -e "\n"
       
       find "$root_path" -type f | grep -v '/\.zfs/' | while IFS= read -r filepath; do
           stat -c '%s|%D:%i|%n' "$filepath" 2>/dev/null
       done >> files_list.txt

       shift
    done
else
    echo "Unsupported OS type: $OSTYPE"
    exit 1
fi


echo_debug "Contents of files_list.txt:"
if [ "$debug_flag" = true ]; then
    cat files_list.txt
fi

# Sort files_list.txt by size, then device/inode (size smallest to largest)
sort -n -k1,2 -t '|' -r files_list.txt > sorted_files_list.txt

echo_debug "Contents of sorted_files_list.txt:"
if [ "$debug_flag" = true ]; then
    cat sorted_files_list.txt
fi


# Use awk to group paths by inode key and handle spaces in paths
awk -F'|' '{
    keyA = $1
    keyB = $2
    path = substr($0, length(keyB) + length(keyA)+3)
    if (keyA == prev_keyA) {
        if (keyB == prev_keyB) {
           print "\t" path
        }
        else {
          if (NR > 1) {
              #Do nothing
          }
          print keyB
          print "\t" path
          prev_keyB = keyB
        }
    } else {
        if (NR > 1) {
            # Do nothing
        }
        print keyB
        print "\t" path
        prev_keyA = keyA
    }
}' sorted_files_list.txt > grouped_inodes.txt

echo_debug "Contents of grouped_inodes.txt:"
if [ "$debug_flag" = true ]; then
    cat grouped_inodes.txt
fi

# Count number of inode groups
file_count=$(grep -c '^\w' grouped_inodes.txt)

color_echo "$Cyan" "  Number of files to process: ${file_count}"

# Initialize current_index
current_index=0

# Create db file
if [ "${passes_flag}" -ge 1 ]; then
    touch "./${rebalance_db_file_name}"
    
    # Sort the text database cleanly using awk paired lines instead of paste command
    if [ -s "./${rebalance_db_file_name}" ]; then
        awk 'NR%2{p=$0;next} {print p "|" $0}' "./${rebalance_db_file_name}" | sort -t '|' -k1,1 | awk -F'|' '{print $1; print $2}' > "./${rebalance_db_file_name}.tmp"
        mv "./${rebalance_db_file_name}.tmp" "./${rebalance_db_file_name}"
    fi

    # Populate the flat tracking cache reference notice
    load_rebalance_db_to_memory
fi

paths=()

# Read grouped_inodes.txt line by line
while IFS= read -r line; do
    if [[ "$line" == $'\t'* ]]; then
        # This is a path line
        path="${line#$'\t'}"
        paths+=("$path")
    else
        # This is a new inode key
        if [[ "${#paths[@]}" -gt 0 ]]; then
            # Process the previous group
            process_inode_group "${paths[@]}"
        fi
        paths=()
    fi
done < grouped_inodes.txt

# Process the last group after the loop ends
if [[ "${#paths[@]}" -gt 0 ]]; then
    process_inode_group "${paths[@]}"
fi

echo ""
echo ""
color_echo "$Green" "Done!"
