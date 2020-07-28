#!/usr/bin/env bash

# exit script on error
set -e
# exit on undeclared variable
set -u

function rebalance () {
    file_path=$1

    tmp_extension=".balance"

    echo "${file_path}"
    echo "Copying '${file_path}' to '${file_path}${tmp_extension}'..."
    # -a -- keep attributes
    # -d -- keep symlinks (dont copy target)
    # -x -- stay on one system
    # -p -- preserve ACLs too
    cp -adxp "${file_path}" "${file_path}${tmp_extension}"

    echo "Removing original '${file_path}'..."
    rm "${file_path}"

    echo "Renaming temporary copy to original '${file_path}'..."
    mv "${file_path}${tmp_extension}" "${file_path}"
}

root_path=$1
# recursively scan through files and execute "rebalance" procedure
find "$root_path" -type f -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
echo Done!
