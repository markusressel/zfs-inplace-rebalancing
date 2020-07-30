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
  echo "Usage: zfs-inplace-rebalancing -checksum true -passes 1 /my/pool"
}

# print a given text entirely in a given color
function color_echo () {
    color=$1
    text=$2
    echo -e "${color}${text}${Color_Off}"
}


function get_rebalance_count () {
    file_path=$1

    line_nr=$(grep -n "${file_path}" "./${rebalance_db_file_name}" | head -n 1 | cut -d: -f1)
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

    current_index="$((current_index + 1))"
    progress_percent=$(echo "scale=2; ${current_index}*100/${file_count}" | bc)
    color_echo "${Cyan}" "Progress -- Files: ${current_index}/${file_count} (${progress_percent}%)" 

    # check if target rebalance count is reached
    rebalance_count=$(get_rebalance_count "${file_path}")
    if [ "${rebalance_count}" -ge "${passes_flag}" ]; then
      color_echo "${Yellow}" "Rebalance count (${passes_flag}) reached, skipping: ${file_path}"
      return
    fi
   
    tmp_extension=".balance"
    tmp_file_path="${file_path}${tmp_extension}"

    echo "Copying '${file_path}' to '${tmp_file_path}'..."
    if [[ "${OSTYPE,,}" == "linux-gnu"* ]]; then
        # Linux

        # -a -- keep attributes
        # -d -- keep symlinks (dont copy target)
        # -x -- stay on one system
        # -p -- preserve ACLs too
        cp -adxp "${file_path}" "${tmp_file_path}"
    elif [[ "${OSTYPE,,}" == "darwin"* ]] || [[ "${OSTYPE,,}" == "freebsd"* ]]; then
        # Mac OS
        # FreeBSD

        # -a -- Archive mode.  Same as -RpP.
        # -x -- File system mount points are not traversed.
        # -p -- Cause cp to preserve the following attributes of each source file
        #       in the copy: modification time, access time, file flags, file mode,
        #       ACL, user ID, and group ID, as allowed by permissions.
        cp -axp "${file_path}" "${tmp_file_path}"
    else
        echo "Unsupported OS type: $OSTYPE"
        exit 1
    fi

    # compare copy against original to make sure nothing went wrong
    if [[ "${checksum_flag,,}" == "true"* ]]; then
        echo "Comparing copy against original..."
        if [[ "${OSTYPE,,}" == "linux-gnu"* ]]; then
            # Linux

            # file attributes
            original_md5=$(lsattr "${file_path}" | awk '{print $1}')
            # file permissions, owner, group
            original_md5="${original_md5} $(ls -lha "${file_path}" | awk '{print $1 " " $3 " " $4}')"
            # file content
            original_md5="${original_md5} $(md5sum -b "${file_path}" | awk '{print $1}')"

            # file attributes
            copy_md5=$(lsattr "${tmp_file_path}" | awk '{print $1}')
            # file permissions, owner, group
            copy_md5="${copy_md5} $(ls -lha "${tmp_file_path}" | awk '{print $1 " " $3 " " $4}')"
            # file content
            copy_md5="${copy_md5} $(md5sum -b "${tmp_file_path}" | awk '{print $1}')"
        elif [[ "${OSTYPE,,}" == "darwin"* ]] || [[ "${OSTYPE,,}" == "freebsd"* ]]; then
            # Mac OS
            # FreeBSD

            # file attributes
            original_md5=$(lsattr "${file_path}" | awk '{print $1}')
            # file permissions, owner, group
            original_md5="${original_md5} $(ls -lha "${file_path}" | awk '{print $1 " " $3 " " $4}')"
            # file content
            original_md5="${original_md5} $(md5 -q "${file_path}")"

            # file attributes
            copy_md5=$(lsattr "${tmp_file_path}" | awk '{print $1}')
            # file permissions, owner, group
            copy_md5="${copy_md5} $(ls -lha "${tmp_file_path}" | awk '{print $1 " " $3 " " $4}')"
            # file content
            copy_md5="${copy_md5} $(md5 -q "${tmp_file_path}")"
        else
            echo "Unsupported OS type: $OSTYPE"
            exit 1
        fi

        if [[ "${original_md5}" == "${copy_md5}"* ]]; then
            color_echo "${Green}" "MD5 OK"
        else
            color_echo "${Red}" "MD5 FAILED: ${original_md5} != ${copy_md5}"
            exit 1
        fi
    fi

    echo "Removing original '${file_path}'..."
    rm "${file_path}"

    echo "Renaming temporary copy to original '${file_path}'..."
    mv "${tmp_file_path}" "${file_path}"

    # update rebalance "database"
    line_nr=$(grep -n "${file_path}" "./${rebalance_db_file_name}" | head -n 1 | cut -d: -f1)
    if [ -z "${line_nr}" ]; then
      rebalance_count=1
      echo "${file_path}" >> "./${rebalance_db_file_name}"
      echo "${rebalance_count}" >> "./${rebalance_db_file_name}"
    else
      rebalance_count_line_nr="$((line_nr + 1))"
      rebalance_count="$((rebalance_count + 1))"
      sed -i "${rebalance_count_line_nr}s/.*/${rebalance_count}/" "./${rebalance_db_file_name}"
    fi
}

checksum_flag='true'
passes_flag='1'

if [ "$#" -eq 0 ]; then
    print_usage
    exit 0
fi

while true ; do
    case "$1" in
        -checksum )
            if [ "$2" -eq 1 ] || [[ "$2" =~ (on|true|yes) ]]; then
                checksum_flag="true"
            else
                checksum_flag="false"
            fi
            shift 2
        ;;
        -count )
            passes_flag=$2
            shift 2
        ;;
        *)
            break
        ;;
    esac 
done;

root_path=$1

color_echo "$Cyan" "Start rebalancing:"
color_echo "$Cyan" "  Path: ${root_path}"
color_echo "$Cyan" "  Rebalancing Passes: ${passes_flag}"
color_echo "$Cyan" "  Use Checksum: ${checksum_flag}"

# count files
file_count=$(find "${root_path}" -type f | wc -l)
color_echo "$Cyan" "  File count: ${file_count}"

# create db file
touch "./${rebalance_db_file_name}"

# recursively scan through files and execute "rebalance" procedure
find "$root_path" -type f -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
echo ""
echo ""
color_echo "$Green" "Done!"
