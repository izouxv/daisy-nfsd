#!/bin/bash

#
# Usage:  ./run-dafny-nfs.sh  go run ./cmd/fs-smallfile
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# root of repo
cd $DIR/..

disk_file=/dev/shm/nfs.img
cpu_list=""
extra_args=()
while true; do
    case "$1" in
    -disk)
        shift
        disk_file="$1"
        shift
        ;;
    --cpu-list)
        shift
        cpu_list="$1"
        shift
        ;;
    # some argument in -foo=value syntax
    -*=*)
        extra_args+=("$1")
        shift
        ;;
    -*)
        extra_args+=("$1" "$2")
        shift
        shift
        ;;
    *)
        break
        ;;
    esac
done

set -eu

# empty disk file is valid and uses MemDisk
if [ -n "$disk_file" ]; then
    rm -f "$disk_file"
    dd status=none if=/dev/zero of="$disk_file" bs=4K count=100000
    sync "$disk_file"
fi

if [ -z "$cpu_list" ]; then
    ./bench/start-dafny-nfs.sh -disk "$disk_file" "${extra_args[@]}" || exit 1
else
    taskset --cpu-list "$cpu_list" ./bench/start-dafny-nfs.sh -disk "$disk_file" "${extra_args[@]}" || exit 1
fi

function cleanup {
    ./bench/stop-dafny-nfs.sh
    rm -f "$disk_file"
}
trap cleanup EXIT

# taskset 0x3 $1 /mnt/nfs
echo "run $@" 1>&2
"$@"
