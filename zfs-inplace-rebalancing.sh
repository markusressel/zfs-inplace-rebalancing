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
Color_Off='\033[0m' # Text Reset

# Regular Colors
Red='\033[0;31m'    # Red
Green='\033[0;32m'  # Green
Yellow='\033[0;33m' # Yellow
Cyan='\033[0;36m'   # Cyan

## Functions

# print a help message
function print_usage() {
    echo "Usage: zfs-inplace-rebalancing --checksum true --skip-hardlinks false --passes 1 /my/pool"
}

# print a given text entirely in a given color
function color_echo() {
    color=$1
    text=$2
    echo -e "${color}${text}${Color_Off}"
}

function get_rebalance_count() {
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
function rebalance() {
    file_path=$1

    # check if file has >=2 links in the case of --skip-hardlinks
    # this shouldn't be needed in the typical case of `find` only finding files with links == 1
    # but this can run for a long time, so it's good to double check if something changed
    if [[ "${skip_hardlinks_flag}" == "true"* ]]; then
        if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
            # Linux
            #
            #  -c  --format=FORMAT
            #      use the specified FORMAT instead of the default; output a
            #      newline after each use of FORMAT
            #  %h     number of hard links

            hardlink_count=$(stat -c "%h" "${file_path}")
        elif [[ "${OSTYPE}" == "darwin"* ]] || [[ "${OSTYPE}" == "freebsd"* ]]; then
            # Mac OS
            # FreeBSD
            #  -f format
            #  Display information using the specified format
            #   l       Number of hard links to file (st_nlink)

            hardlink_count=$(stat -f %l "${file_path}")
        else
            echo "Unsupported OS type: $OSTYPE"
            exit 1
        fi

        if [ "${hardlink_count}" -ge 2 ]; then
            echo "Skipping hard-linked file: ${file_path}"
            return
        fi
    fi

    current_index="$((current_index + 1))"
    progress_percent=$(printf '%0.2f' "$((current_index * 10000 / file_count))e-2")
    color_echo "${Cyan}" "Progress -- Files: ${current_index}/${file_count} (${progress_percent}%)"

    if [[ ! -f "${file_path}" ]]; then
        color_echo "${Yellow}" "File is missing, skipping: ${file_path}"
    fi

    if [ "${passes_flag}" -ge 1 ]; then
        # check if target rebalance count is reached
        rebalance_count=$(get_rebalance_count "${file_path}")
        if [ "${rebalance_count}" -ge "${passes_flag}" ]; then
            color_echo "${Yellow}" "Rebalance count (${passes_flag}) reached, skipping: ${file_path}"
            return
        fi
    fi

    tmp_extension=".balance"
    tmp_file_path="${file_path}${tmp_extension}"

    echo "Copying '${file_path}' to '${tmp_file_path}'..."
    if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
        # Linux

        # --reflink=never -- force standard copy (see ZFS Block Cloning)
        # -a -- keep attributes, includes -d -- keep symlinks (dont copy target) and
        #       -p -- preserve ACLs to
        # -x -- stay on one system
        cp --reflink=never -ax "${file_path}" "${tmp_file_path}"
    elif [[ "${OSTYPE}" == "darwin"* ]] || [[ "${OSTYPE}" == "freebsd"* ]]; then
        # Mac OS
        # FreeBSD

        # -a -- Archive mode.  Same as -RpP. Includes preservation of modification
        #       time, access time, file flags, file mode, ACL, user ID, and group
        #       ID, as allowed by permissions.
        # -x -- File system mount points are not traversed.
        cp -ax "${file_path}" "${tmp_file_path}"
    else
        echo "Unsupported OS type: $OSTYPE"
        exit 1
    fi

    # compare copy against original to make sure nothing went wrong
    if [[ "${checksum_flag}" == "true"* ]]; then
        echo "Comparing copy against original..."
        if [[ "${OSTYPE}" == "linux-gnu"* ]]; then
            # Linux

            # file attributes
            original_md5=$(lsattr "${file_path}")
            # remove anything after the last space
            original_md5=${original_md5% *}
            # file permissions, owner, group, size, modification time
            original_md5="${original_md5} $(stat -c "%A %U %G %s %Y" "${file_path}")"
            # file content
            original_md5="${original_md5} $(md5sum -b "${file_path}")"


            # file attributes
            copy_md5=$(lsattr "${tmp_file_path}")
            # remove anything after the last space
            copy_md5=${copy_md5% *}
            # file permissions, owner, group, size, modification time
            copy_md5="${copy_md5} $(stat -c "%A %U %G %s %Y" "${tmp_file_path}")"
            # file content
            copy_md5="${copy_md5} $(md5sum -b "${tmp_file_path}")"
            # remove the temporary extension
            copy_md5=${copy_md5%"${tmp_extension}"}
        elif [[ "${OSTYPE}" == "darwin"* ]] || [[ "${OSTYPE}" == "freebsd"* ]]; then
            # Mac OS
            # FreeBSD

            # note: no lsattr on Mac OS or FreeBSD

            # file permissions, owner, group size, modification time
            original_md5="$(stat -f "%Sp %Su %Sg %z %m" "${file_path}")"
            # file content
            original_md5="${original_md5} $(md5 -q "${file_path}")"

            # file permissions, owner, group size, modification time
            copy_md5="$(stat -f "%Sp %Su %Sg %z %m" "${tmp_file_path}")"
            # file content
            copy_md5="${copy_md5} $(md5 -q "${tmp_file_path}")"
            # remove the temporary extension
            copy_md5=${copy_md5%"${tmp_extension}"}
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

    if [ "${passes_flag}" -ge 1 ]; then
        # update rebalance "database"
        line_nr=$(grep -xF -n "${file_path}" "./${rebalance_db_file_name}" | head -n 1 | cut -d: -f1)
        if [ -z "${line_nr}" ]; then
            rebalance_count=1
            echo "${file_path}" >>"./${rebalance_db_file_name}"
            echo "${rebalance_count}" >>"./${rebalance_db_file_name}"
        else
            rebalance_count_line_nr="$((line_nr + 1))"
            rebalance_count="$((rebalance_count + 1))"
            sed -i '' "${rebalance_count_line_nr}s/.*/${rebalance_count}/" "./${rebalance_db_file_name}"
        fi
    fi
}

checksum_flag='true'
skip_hardlinks_flag='false'
passes_flag='1'

if [[ "$#" -eq 0 ]]; then
    print_usage
    exit 0
fi

while true; do
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
    --skip-hardlinks)
        if [[ "$2" == 1 || "$2" =~ (on|true|yes) ]]; then
            skip_hardlinks_flag="true"
        else
            skip_hardlinks_flag="false"
        fi
        shift 2
        ;;
    -p | --passes)
        passes_flag=$2
        shift 2
        ;;
    *)
        break
        ;;
    esac
done

root_path=$1

color_echo "$Cyan" "Start rebalancing $(date):"
color_echo "$Cyan" "  Path: ${root_path}"
color_echo "$Cyan" "  Rebalancing Passes: ${passes_flag}"
color_echo "$Cyan" "  Use Checksum: ${checksum_flag}"
color_echo "$Cyan" "  Skip Hardlinks: ${skip_hardlinks_flag}"

# count files
if [[ "${skip_hardlinks_flag}" == "true"* ]]; then
    file_count=$(find "${root_path}" -type f -links 1 | wc -l)
else
    file_count=$(find "${root_path}" -type f | wc -l)
fi

color_echo "$Cyan" "  File count: ${file_count}"

# create db file
if [ "${passes_flag}" -ge 1 ]; then
    touch "./${rebalance_db_file_name}"
fi

# recursively scan through files and execute "rebalance" procedure
# in the case of --skip-hardlinks, only find files with links == 1
if [[ "${skip_hardlinks_flag}" == "true"* ]]; then
    find "$root_path" -type f -links 1 -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
else
    find "$root_path" -type f -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
fi

echo ""
echo ""
color_echo "$Green" "Done!"
