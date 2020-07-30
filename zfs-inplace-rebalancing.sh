#!/usr/bin/env bash

# exit script on error
set -e
# exit on undeclared variable
set -u

# index used for progress
current_index=0

## Color Constants

# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Cyan='\033[0;36m'         # Cyan

## Functions

# print a given text entirely in a given color
function color_echo () {
    color=$1
    text=$2
    echo -e "${color}${text}${Color_Off}"
}

# rebalance a specific file
function rebalance () {
    file_path=$1

    current_index="$((current_index + 1))"
    progress_percent=$(echo "scale=2; ${current_index}*100/${file_count}" | bc)
    color_echo "$Cyan" "Progress -- Files: ${current_index}/${file_count} (${progress_percent}%)" 
   
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

    echo "Removing original '${file_path}'..."
    rm "${file_path}"

    echo "Renaming temporary copy to original '${file_path}'..."
    mv "${tmp_file_path}" "${file_path}"
}

root_path=$1

# count files
file_count=$(find "$root_path" -type f | wc -l)
echo "Files to rebalance: $file_count"

# recursively scan through files and execute "rebalance" procedure
find "$root_path" -type f -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
echo ""
echo ""
color_echo "$Green" "Done!"
