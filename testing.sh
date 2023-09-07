#!/usr/bin/env bash

# exit script on error
set -e
# exit on undeclared variable
set -u

log_std_file=./test.log
log_error_file=./error.log
test_data_src=./test/pool
test_pool_data_path=./testing_data

function prepare() {
  # cleanup
  rm -f $log_std_file
  rm -f $log_error_file
  rm -f rebalance.db
  rm -rf $test_pool_data_path

  # setup
  cp -rf $test_data_src $test_pool_data_path
}

function assertions() {
  # check error log is empty
  if grep -q '[^[:space:]]' $log_error_file; then
    echo "error log is not empty!"
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

prepare
./zfs-inplace-rebalancing.sh $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
assertions

prepare
./zfs-inplace-rebalancing.sh --checksum true --passes 1 $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
assertions

prepare
./zfs-inplace-rebalancing.sh --checksum false $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
assertions

prepare
ln "$test_pool_data_path/projects/[2020] some project/mp4.txt" "$test_pool_data_path/projects/[2020] some project/mp4.txt.link"
./zfs-inplace-rebalancing.sh --skip-hardlinks false $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
# Both link files should be copied
assert_matching_file_copied "mp4.txt"
assert_matching_file_copied "mp4.txt.link"
assertions

prepare
ln "$test_pool_data_path/projects/[2020] some project/mp4.txt" "$test_pool_data_path/projects/[2020] some project/mp4.txt.link"
./zfs-inplace-rebalancing.sh --skip-hardlinks true $test_pool_data_path >> $log_std_file 2>> $log_error_file
cat $log_std_file
# Neither file should be copied now, since they are each a hardlink
assert_matching_file_not_copied "mp4.txt.link"
assert_matching_file_not_copied "mp4.txt"
assertions
