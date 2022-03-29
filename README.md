# zfs-inplace-rebalancing
Simple bash script to rebalance pool data between all mirrors when adding vdevs to a pool.

[![asciicast](https://asciinema.org/a/350222.svg)](https://asciinema.org/a/350222)

## How it works

This script recursively traverses all the files in a given directory. Each file is copied with a `.rebalance` suffix, retaining all file attributes. The original is then deleted and the *copy* is renamed back to the name of the original file. When copying a file ZFS will spread the data blocks across all vdevs, effectively distributing/rebalancing the data of the original file (more or less) evenly. This allows the pool data to be rebalanced without the need for a separate backup pool/drive.

Note that this process is not entirely "in-place", since a file has to be fully copied before the original is deleted. The term is used to make it clear that no additional pool (and therefore hardware) is necessary to use this script. However, this also means that you have to have enough space to create a copy of the biggest file in your target directory for it to work.

At no point in time are both versions of the original file deleted.
To make sure file attributes, permissions and file content are maintained when copying the original file, all attributes and the file checksum is compared before removing the original file (if not disabled using `--checksum false`).

Since file attributes are fully retained, it is not possible to verify if an individual file has been rebalanced. However, this script keeps track of rebalanced files by maintaining a "database" file in its working directory called `rebalance_db.txt` (if not disabled using `--passes 0`). This file contains two lines of text for each processed file:

* One line for the file path
* and the next line for the current count of rebalance passes

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
> zpool list -v

NAME                                              SIZE  ALLOC   FREE  CKPOINT  EXPANDSZ   FRAG    CAP  DEDUP    HEALTH  ALTROOT
bpool                                            1.88G   113M  1.76G        -         -     2%     5%  1.00x    ONLINE  -
  mirror                                         1.88G   113M  1.76G        -         -     2%  5.88%      -    ONLINE  
    ata-Samsung_SSD_860_EVO_500GB_J0NBL-part2        -      -      -        -         -      -      -      -    ONLINE  
    ata-Samsung_SSD_860_EVO_500GB_S4XB-part2         -      -      -        -         -      -      -      -    ONLINE  
rpool                                             460G  3.66G   456G        -         -     0%     0%  1.00x    ONLINE  -
  mirror                                          460G  3.66G   456G        -         -     0%  0.79%      -    ONLINE  
    ata-Samsung_SSD_860_EVO_500GB_S4BB-part3         -      -      -        -         -      -      -      -    ONLINE  
    ata-Samsung_SSD_860_EVO_500GB_S4XB-part3         -      -      -        -         -      -      -      -    ONLINE  
vol1                                             9.06T  3.77T  5.29T        -         -    13%    41%  1.00x    ONLINE  -
  mirror                                         3.62T  1.93T  1.70T        -         -    25%  53.1%      -    ONLINE  
    ata-WDC_WD40EFRX-68N32N0_WD-WCC                  -      -      -        -         -      -      -      -    ONLINE  
    ata-ST4000VN008-2DR166_ZM4-part2                 -      -      -        -         -      -      -      -    ONLINE  
  mirror                                         3.62T  1.84T  1.78T        -         -     8%  50.9%      -    ONLINE  
    ata-ST4000VN008-2DR166_ZM4-part2                 -      -      -        -         -      -      -      -    ONLINE  
    ata-WDC_WD40EFRX-68N32N0_WD-WCC-part2            -      -      -        -         -      -      -      -    ONLINE  
  mirror                                         1.81T   484K  1.81T        -         -     0%  0.00%      -    ONLINE  
    ata-WDC_WD20EARX-00PASB0_WD-WMA-part2            -      -      -        -         -      -      -      -    ONLINE  
    ata-ST2000DM001-1CH164_Z1E-part2                 -      -      -        -         -      -      -      -    ONLINE  
```

and have a look at difference of the `CAP` value (`SIZE`/`FREE` vs `ALLOC` ratio) between vdevs.

### No Deduplication

Due to the working principle of this script, which essentially creates a duplicate file on purpose, deduplication will most definitely prevent it from working as intended. If you use deduplication you probably have to resort to a more expensive rebalancing method that involves additional drives.

### Data selection (cold data)

Due to the working principle of this script, it is crucial that you **only run it on data that is not actively accessed**, since the original file will be deleted.

### Snapshots

If you do a snapshot of the data you want to balance before starting the rebalancing script, keep in mind that ZFS now has to keep track of all of the data in the target directory twice. Once in the snapshot you made, and once for the new copy. This means that you will effectively use double the file size of all files within the target directory. Therefore it is a good idea to process the pool data in badges and remove old snapshots along the way, since you probably will be hitting the capacity limits of your pool at some point during the rebalancing process.

## Installation

Since this is a simple bash script, there is no package. Simply download the script and make it executable:

```shell
curl -O https://raw.githubusercontent.com/markusressel/zfs-inplace-rebalancing/master/zfs-inplace-rebalancing.sh
chmod +x ./zfs-inplace-rebalancing.sh
```

Dependencies:
* `pacman -S bc` - used for percentage calculation

## Usage

**ALWAYS HAVE A BACKUP OF YOUR DATA!**

You can print a help message by running the script without any parameters:

```shell
./zfs-inplace-rebalancing.sh
```

### Parameters

| Name      | Description | Default |
|-----------|-------------|---------|
| `-c`<br>`--checksum` | Whether to compare attributes and content of the copied file using an **MD5** checksum. Technically this is a redundent check and consumes a lot of resources, so think twice. | `true` |
| `-p`<br>`--passes`   | The maximum number of rebalance passes per file. Setting this to infinity by using a value `<= 0` might improve performance when rebalancing a lot of small files. | `1` |

### Example

Make sure to run this script with a user that has rw permission to all of the files in the target directory.
The easiest way to achieve this is by **running the script as root**.

```shell
sudo su
./zfs-inplace-rebalancing.sh --checksum true --passes 1 /pool/path/to/rebalance
```

To keep track of the balancing progress, you can open another terminal and run:

```shell
watch zpool list -v
```

### Log to File

To write the output to a file, simply redirect stdout and stderr to a file (or separate files).
Since this redirects all output, you will have to follow the contents of the log files to get realtime info:

```shell
# one shell window:
tail -F ./stdout.log
# another shell window:
./zfs-inplace-rebalancing.sh /pool/path/to/rebalance >> ./stdout.log 2>> ./stderr.log
```

### Things to consider

Although this script **does** have a progress output (files as well as percentage) it might be a good idea to try a small subfolder first, or process your pool folder layout in manually selected badges. This can also limit the damage done, if anything bad happens.

When aborting the script midway through, be sure to check the last lines of its output. When cancelling before or during the renaming process a ".rebalance" file might be left and you have to rename (or delete) it manually.

Although the `--passes` parameter can be used to limit the maximum amount of rebalance passes per file, it is only meant to speedup aborted runs. Individual files will **not be process multiple times automatically**. To reach multiple passes you have to run the script on the same target directory multiple times.

# Contributing

GitHub is for social coding: if you want to write code, I encourage contributions through pull requests from forks
of this repository. Create GitHub tickets for bugs and new features and comment on the ones that you are interested in.

# Attributions

This script was inspired by [zfs-balancer](https://github.com/programster/zfs-balancer).

# Disclaimer

This software is provided "as is" and "as available", without any warranty.  
**ALWAYS HAVE A BACKUP OF YOUR DATA!**
