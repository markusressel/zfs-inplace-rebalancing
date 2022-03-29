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
  rm -f rebalance_db.txt
  rm -rf $test_pool_data_path

  # setup
  cp -rf $test_data_src $test_pool_data_path
}

function assertions() {
  # check error log is empty
  if grep -q '[^[:space:]]' $log_error_file; then
    echo "error log is not empty!"
    exit 1
  fi
}

prepare
./zfs-inplace-rebalancing.sh $test_pool_data_path >> $log_std_file 2>> $log_error_file
assertions

prepare
./zfs-inplace-rebalancing.sh --checksum true --passes 1 $test_pool_data_path >> $log_std_file 2>> $log_error_file
assertions

prepare
./zfs-inplace-rebalancing.sh --checksum false $test_pool_data_path >> $log_std_file 2>> $log_error_file
assertions
