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
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

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
    color_echo "$Green" "Progress -- Files: ${current_index}/${file_count} (${progress_percent}%)" 
   
    tmp_extension=".balance"

    echo "Copying '${file_path}' to '${file_path}${tmp_extension}'..."
    if [[ "${OSTYPE,,}" == "linux-gnu"* ]]; then
        # Linux

        # -a -- keep attributes
        # -d -- keep symlinks (dont copy target)
        # -x -- stay on one system
        # -p -- preserve ACLs too
        cp -adxp "${file_path}" "${file_path}${tmp_extension}"
    elif [[ "${OSTYPE,,}" == "darwin"* ]]; then
        # Mac OSX

        # (should be the same as bsd, but untested!)

        # -a -- keep attributes
        # -d -- keep symlinks (dont copy target)
        # -x -- stay on one system
        # -p -- preserve ACLs too
        cp -adxp "${file_path}" "${file_path}${tmp_extension}"
    elif [[ "${OSTYPE,,}" == "freebsd"* ]]; then
        # FreeBSD

        # -a -- Archive mode.  Same as -RpP.
        # -x -- File system mount points are not traversed.
        # -p -- Cause cp to preserve the following attributes of each source file
        #       in the copy: modification time, access time, file flags, file mode,
        #       ACL, user ID, and group ID, as allowed by permissions.
        cp -axp "${file_path}" "${file_path}${tmp_extension}"
    else
        echo "Unsupported OS type: $OSTYPE"
        exit 1
    fi

    echo "Removing original '${file_path}'..."
    rm "${file_path}"

    echo "Renaming temporary copy to original '${file_path}'..."
    mv "${file_path}${tmp_extension}" "${file_path}"
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
