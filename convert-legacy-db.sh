#!/bin/bash
set -eu

####
#### This script converts legacy "rebalance_db.txt" database file to new "rebalance.db" format
#### It utilizes a CSV intermediary as this is the fastest way of ingesting a large dataset into SQLite
####

rebalance_db_file_name='rebalance_db.txt'
rebalance_sqldb_file='rebalance.db'
rebalance_csv_tmp='rebalance.csv_tmp'

echo "Importing ${rebalance_db_file_name} into ${rebalance_sqldb_file}..."

echo "Creating SQL database at ${rebalance_sqldb_file}"
# ensures it's FOR SURE an empty db
sqlite3 "${rebalance_sqldb_file}" 'create table balancing (file string primary key, passes integer)'

total=$(($(cat "${rebalance_db_file_name}" | wc -l) / 2))
done=0
path=''
echo "Generating CSV at ${rebalance_csv_tmp}"
echo -n > "${rebalance_csv_tmp}"
while IFS="" read -r line || [ -n "$line" ]; do
    if [[ -z "${path}" ]]; then
        path="${line}"
        continue
    fi

    echo "\"${path//\"/\"\"}\",${line}" >> "${rebalance_csv_tmp}"
    path=''
    echo -e -n "\r=> Generated $((done+=1)) of ${total} lines"
done < "./${rebalance_db_file_name}"
echo -e "\r=> Processed ${total} items to CSV at ${rebalance_csv_tmp}"

echo "Importing data to ${rebalance_sqldb_file}..."
sqlite3 "${rebalance_sqldb_file}" '.mode csv' ".import ${rebalance_csv_tmp} balancing"

echo "Optimizing database..."
sqlite3 "${rebalance_sqldb_file}" 'VACUUM'

echo 'Cleaning up...'
rm "${rebalance_csv_tmp}"
mv "${rebalance_db_file_name}" "${rebalance_sqldb_file}_legacy"
