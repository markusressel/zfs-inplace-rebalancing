# zfs-inplace-rebalancing
Simple bash script to rebalance pool data between all mirrors when adding vdevs to a pool.

## How it works

This script simply copies all files, deletes the original and renames the copy back to the original name. The given root directory is traversed recursively (using `find`) and each file is processed individually. At no point in time are both versions of the original file deleted.

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

```
chmod +x ./zfs-in-place-mirror-rebalance.sh
./zfs-in-place-mirror-rebalance.sh /pool/path/to/rebalance
```

Note that this script does **not** have any kind of progress bar (yet), so it might be a good idea to try a small subfolder first, or process your pool folder layout in manually selected badges.

When aborting the script midway through, be sure to check the last lines of its output. When cancelling before or during the renaming process a ".rebalance" file might be left and you have to rename it manually.

## Attributions

This script was inspired by [zfs-balancer](https://github.com/programster/zfs-balancer).

## Disclaimer

This software is provided "as is" and "as available", without any warranty.  
**ALWAYS HAVE A BACKUP OF YOUR DATA!**
