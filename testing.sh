#!/usr/bin/env bash

# exit script on error
set -e
# exit on undeclared variable
set -u

log_std_file=./test.log
log_error_file=./error.log
test_data_src=./test/pool
test_pool_data_path=./testing_data

## Color Constants

# Reset
Color_Off='\033[0m' # Text Reset

# Regular Colors
Red='\033[0;31m'    # Red
Green='\033[0;32m'  # Green
Yellow='\033[0;33m' # Yellow
Cyan='\033[0;36m'   # Cyan

## Functions

# print a given text entirely in a given color
function color_echo () {
  color=$1
  text=$2
  echo -e "${color}${text}${Color_Off}"
}

function prepare() {
  # cleanup
  rm -f $log_std_file
  rm -f $log_error_file
  rm -f rebalance_db.txt
  rm -rf $test_pool_data_path

  # setup
  cp -rf $test_data_src $test_pool_data_path
}

function assertions() {
  # check error log is empty
  if grep -q '[^[:space:]]' $log_error_file; then
    color_echo "$Red" "error log is not empty!"
    cat $log_error_file
    exit 1
  fi
}

function assert_matching_file_copied() {
  if ! grep "Copying" $log_std_file | grep -q "$1"; then
    echo "File matching '$1' was not copied when it should have been!"
    exit 1
  fi
}

function assert_matching_file_not_copied() {
  if grep "Copying" $log_std_file | grep -q "$1"; then
    echo "File matching '$1' was copied when it should have been skipped!"
    exit 1
  fi
}

color_echo "$Cyan" "Running tests..."

color_echo "$Cyan" "Running tests with default options..."
prepare
./zfs-inplace-rebalancing.sh $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
assertions
color_echo "$Green" "Tests passed!"

color_echo "$Cyan" "Running tests with checksum true and 1 pass..."
prepare
./zfs-inplace-rebalancing.sh --checksum true --passes 1 $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
assertions
color_echo "$Green" "Tests passed!"

color_echo "$Cyan" "Running tests with checksum false..."
prepare
./zfs-inplace-rebalancing.sh --checksum false $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
assertions
color_echo "$Green" "Tests passed!"

color_echo "$Cyan" "Running tests with skip-hardlinks false..."
prepare
ln "$test_pool_data_path/projects/[2020] some project/mp4.txt" "$test_pool_data_path/projects/[2020] some project/mp4.txt.link"
./zfs-inplace-rebalancing.sh --skip-hardlinks false $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
# Both link files should be copied
assert_matching_file_copied "mp4.txt"
assert_matching_file_copied "mp4.txt.link"
assertions
color_echo "$Green" "Tests passed!"

color_echo "$Cyan" "Running tests with skip-hardlinks true..."
prepare
ln "$test_pool_data_path/projects/[2020] some project/mp4.txt" "$test_pool_data_path/projects/[2020] some project/mp4.txt.link"
./zfs-inplace-rebalancing.sh --skip-hardlinks true $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
# Neither file should be copied now, since they are each a hardlink
assert_matching_file_not_copied "mp4.txt.link"
assert_matching_file_not_copied "mp4.txt"
assertions
color_echo "$Green" "Tests passed!"

color_echo "$Green" "All tests passed!"