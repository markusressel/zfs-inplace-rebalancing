#!/usr/bin/env bash

# exit script on error
set -e
# exit on undeclared variable
set -u

test_data_src=./test/pool
test_pool_data_path=./testing_data

function prepare() {
    rm -f rebalance_db.txt
    rm -rf $test_pool_data_path
    cp -rf $test_data_src $test_pool_data_path
}

prepare
./zfs-inplace-rebalancing.sh $test_pool_data_path

prepare
./zfs-inplace-rebalancing.sh --checksum true --passes 1 $test_pool_data_path

prepare
./zfs-inplace-rebalancing.sh --checksum false $test_pool_data_path
