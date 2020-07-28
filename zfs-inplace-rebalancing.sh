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

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux

        # -a -- keep attributes
        # -d -- keep symlinks (dont copy target)
        # -x -- stay on one system
        # -p -- preserve ACLs too
        cp -adxp "${file_path}" "${file_path}${tmp_extension}"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # Mac OSX

        # (should be the same as bsd, but untested!)

        # -a -- keep attributes
        # -d -- keep symlinks (dont copy target)
        # -x -- stay on one system
        # -p -- preserve ACLs too
        cp -adxp "${file_path}" "${file_path}${tmp_extension}"
    elif [[ "$OSTYPE" == "freebsd"* ]]; then
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
# recursively scan through files and execute "rebalance" procedure
find "$root_path" -type f -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
echo ""
echo ""
echo "Done!"
