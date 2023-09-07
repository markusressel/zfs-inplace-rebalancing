#!/usr/bin/env bash

# exit script on error
set -e
# exit on undeclared variable
set -u

# processed files database runtime variables
rebalance_db_file_name="rebalance.db"

# keeps changes before these are persisted to the database
rebalance_db_cache='' #database filename
rebalance_db_save_interval=60 # how often changes are persisted to the database in seconds
rebalance_db_last_save=$SECONDS # when the database was last persisted

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
  echo "Usage: zfs-inplace-rebalancing --checksum true --skip-hardlinks false --passes 1 /my/pool"
}

# print a given text entirely in a given color
function color_echo () {
    color=$1
    text=$2
    echo -e "${color}${text}${Color_Off}"
}

# Loads existing rebalance database, or creates a new one. Requires no parameters.
function init_database () {
  if [[ "${passes_flag}" -le 0 ]]; then
    echo "skipped (--passes <= 0 requested)"
    return
  fi

  if [[ ! -r "${rebalance_db_file_name}" ]]; then # database unreadable => either no db or no permissions
    # try to create a new db - if this is a permission problem this will crash [as intended]
    sqlite3 "${rebalance_db_file_name}" "CREATE TABLE balancing (file string primary key, passes integer)"
    echo "initialized in ${rebalance_db_file_name}"
  else # db is readable - do a simple sanity check to make sure it isn't broken/locked
    local balanced
    balanced=$(sqlite3 "${rebalance_db_file_name}" "SELECT COUNT(*) FROM balancing")
    echo "found ${balanced} records in ${rebalance_db_file_name}"
  fi
}

# Provides number of already completed balancing passes for a given file
# Use: get_rebalance_count "/path/to/file"
# Output: a non-negative integer
function get_rebalance_count () {
    local count
    count=$(sqlite3 "${rebalance_db_file_name}" "SELECT passes FROM balancing WHERE file = '${1//'/\'}'")
    echo "${count:-0}"
}

function persist_database () {
  color_echo "${Cyan}" "Flushing database changes..."
  sqlite3 "${rebalance_db_file_name}" <<< "BEGIN TRANSACTION;${rebalance_db_cache};COMMIT;"
  rebalance_db_cache=''
  rebalance_db_last_save=$SECONDS
}

# Sets number of completed balancing passes for a given file
# Use: set_rebalance_count "/path/to/file" 123
function set_rebalance_count () {
    rebalance_db_cache="${rebalance_db_cache};INSERT OR REPLACE INTO balancing VALUES('${1//'/\'}', $2);"
    color_echo "${Green}" "File $1 completed $2 rebalance cycles"

    # this is slightly "clever", as there's no way to access monotonic time in shell.
    # $SECONDS contains a wall clock time since shell starting, but it's affected
    #  by timezones and system time changes. "time_since_last" will calculate absolute
    #  difference since last DB save. It may not be correct, but unless the time
    #  changes constantly, it will save *at least* every $rebalance_db_save_time
    local time_now=$SECONDS
    local time_since_last=$(($time_now >= $rebalance_db_last_save ? $time_now - $rebalance_db_last_save : $rebalance_db_last_save - $time_now))
    if [[ $time_since_last -gt $rebalance_db_save_interval ]]; then
        persist_database
    fi
}

# Rebalance a specific file
# Use: rebalance "/path/to/file"
# Output: log lines
function rebalance () {
    local file_path
    file_path=$1

    # check if file has >=2 links in the case of --skip-hardlinks
    # this shouldn't be needed in the typical case of `find` only finding files with links == 1
    # but this can run for a long time, so it's good to double check if something changed
    if [[ "${skip_hardlinks_flag,,}" == "true"* ]]; then
        hardlink_count=$(stat -c "%h" "${file_path}")

        if [ "${hardlink_count}" -ge 2 ]; then
            echo "Skipping hard-linked file: ${file_path}"
            return
        fi
    fi

    current_index="$((current_index + 1))"
    progress_percent=$(perl -e "printf('%0.2f', ${current_index}*100/${file_count})")
    color_echo "${Cyan}" "Progress -- Files: ${current_index}/${file_count} (${progress_percent}%)"

    if [[ ! -f "${file_path}" ]]; then
        color_echo "${Yellow}" "File is missing, skipping: ${file_path}"
    fi


    if [[ "${passes_flag}" -ge 1 ]]; then
        # this count is reused later to update database
        local rebalance_count
        rebalance_count=$(get_rebalance_count "${file_path}")

        # check if target rebalance count is reached
        if [[ "${rebalance_count}" -ge "${passes_flag}" ]]; then
          color_echo "${Yellow}" "Rebalance count of ${passes_flag} reached (${rebalance_count}), skipping: ${file_path}"
          return
        fi
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
            # shellcheck disable=SC2012
            original_md5="${original_md5} $(ls -lha "${file_path}" | awk '{print $1 " " $3 " " $4}')"
            # file content
            original_md5="${original_md5} $(md5sum -b "${file_path}" | awk '{print $1}')"

            # file attributes
            copy_md5=$(lsattr "${tmp_file_path}" | awk '{print $1}')
            # file permissions, owner, group
            # shellcheck disable=SC2012
            copy_md5="${copy_md5} $(ls -lha "${tmp_file_path}" | awk '{print $1 " " $3 " " $4}')"
            # file content
            copy_md5="${copy_md5} $(md5sum -b "${tmp_file_path}" | awk '{print $1}')"
        elif [[ "${OSTYPE,,}" == "darwin"* ]] || [[ "${OSTYPE,,}" == "freebsd"* ]]; then
            # Mac OS
            # FreeBSD

            # file attributes
            original_md5=$(lsattr "${file_path}" | awk '{print $1}')
            # file permissions, owner, group
            # shellcheck disable=SC2012
            original_md5="${original_md5} $(ls -lha "${file_path}" | awk '{print $1 " " $3 " " $4}')"
            # file content
            original_md5="${original_md5} $(md5 -q "${file_path}")"

            # file attributes
            copy_md5=$(lsattr "${tmp_file_path}" | awk '{print $1}')
            # file permissions, owner, group
            # shellcheck disable=SC2012
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

    if [ "${passes_flag}" -ge 1 ]; then
        set_rebalance_count "${file_path}" $((rebalance_count + 1))
    fi
}

checksum_flag='true'
skip_hardlinks_flag='false'
passes_flag='1'

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
        --skip-hardlinks )
            if [[ "$2" == 1 || "$2" =~ (on|true|yes) ]]; then
                skip_hardlinks_flag="true"
            else
                skip_hardlinks_flag="false"
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

root_path=$1

# ensure we don't do something unexpected
if [[ -r "rebalance_db.txt" ]]; then
  color_echo "${Red}" 'Found legacy database file in "rebalance_db.txt". To avoid possible unintended operations the process will terminate. You can either convert the legacy database using "convert-legacy-db.sh" script, or simply delete/rename "rebalance_db.txt"'
  exit 2
fi

color_echo "$Cyan" "Start rebalancing:"
color_echo "$Cyan" "  Path: ${root_path}"
color_echo "$Cyan" "  Rebalancing Passes: ${passes_flag}"
color_echo "$Cyan" "  Rebalancing DB: $(init_database)"
color_echo "$Cyan" "  Use Checksum: ${checksum_flag}"
color_echo "$Cyan" "  Skip Hardlinks: ${skip_hardlinks_flag}"

# count files
if [[ "${skip_hardlinks_flag,,}" == "true"* ]]; then
    file_count=$(find "${root_path}" -type f -links 1 | wc -l)
else
    file_count=$(find "${root_path}" -type f | wc -l)
fi

color_echo "$Cyan" "  File count: ${file_count}"

# recursively scan through files and execute "rebalance" procedure
# in the case of --skip-hardlinks, only find files with links == 1
if [[ "${skip_hardlinks_flag,,}" == "true"* ]]; then
    find "$root_path" -type f -links 1 -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
else
    find "$root_path" -type f -print0 | while IFS= read -r -d '' file; do rebalance "$file"; done
fi

# There may be some pending changes as we will almost never hit the interval perfectly - flush it
persist_database

echo ""
echo ""
color_echo "$Green" "Done!"
