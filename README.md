# zfs-inplace-rebalancing
Simple bash script to rebalance pool data between all mirrors when adding vdevs to a pool.

[![asciicast](https://asciinema.org/a/350222.svg)](https://asciinema.org/a/350222)

## How it works

This script recursively traverses all the files in a given directory. Each file is copied with a `.rebalance` suffix, retaining all file attributes. The original is then deleted and the *copy* is renamed back to the name of the original file. When copying a file ZFS will spread the data blocks across all vdevs, effectively distributing/rebalancing the data of the original file (more or less) evenly. This allows the pool data to be rebalanced without the need for a separate backup pool/drive.

Note that this process is not entirely "in-place", since a file has to be fully copied before the original is deleted. The term is used to make it clear that no additional pool (and therefore hardware) is necessary to use this script. However, this also means that you have to have enough space to create a copy of the biggest file in your target directory for it to work.

At no point in time are both versions of the original file deleted.
To make sure file attributes, permissions and file content are maintained when copying the original file, all attributes and the file checksum is compared before removing the original file.

Since file attributes are fully retained, it is not possible to verify if an individual file has been rebalanced. However, this script keeps track of rebalanced files by maintaining a "database" file called `rebalance_db.txt` in its working directory. This file contains two lines of text for each processed file:

* One line for the file path
* and the next line for the current count of rebalances

```text
/my/example/pool/file1.mkv
1
/my/example/pool/file2.mkv
1
```

## Prerequisites

### Balance Status

To check the current balance of a pool use:

```
zpool list -v
```

### No Deduplication

Due to the working principle of this script, which essentially creates a duplicate file on purpose, deduplication will most definitely prevent it from working as intended. If you use deduplication you probably have to resort to a more expensive rebalancing method that involves additional drives.

### Data selection

Due to the working principle of this script, it is crucial that you **only run it on data that is not actively accessed**, since the original file will be deleted.

## Usage

**ALWAYS HAVE A BACKUP OF YOUR DATA!**

You can print a help message by running the script without any parameters:

```
chmod +x ./zfs-inplace-rebalancing.sh
./zfs-inplace-rebalancing.sh
```

### Parameters

| Name      | Description | Default |
|-----------|-------------|---------|
| -checksum | Whether to compare the copy using an **MD5** checksum | `true` |
| -passes   | The maximum number of rebalance passes per file | `1` |

### Example

```
./zfs-inplace-rebalancing.sh -checksum true -passes 1 /pool/path/to/rebalance
```

### Things to consider

Although this script **does** have a progress output (files as well as percentage) it might be a good idea to try a small subfolder first, or process your pool folder layout in manually selected badges. This can also limit the damage done, if anything bad happens.

When aborting the script midway through, be sure to check the last lines of its output. When cancelling before or during the renaming process a ".rebalance" file might be left and you have to rename it manually.

Although the `-passes` paramter can be used to limit the maximum amount of rebalance passes per file, it is only meant to speedup aborted runs. Individual files will **not be process multiple times automatically**. To reach multiple passes you have to run the script on the same target directory multiple times.

## Attributions

This script was inspired by [zfs-balancer](https://github.com/programster/zfs-balancer).

## Disclaimer

This software is provided "as is" and "as available", without any warranty.  
**ALWAYS HAVE A BACKUP OF YOUR DATA!**
