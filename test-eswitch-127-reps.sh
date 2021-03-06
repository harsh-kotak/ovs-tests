#!/bin/bash
#
# Bug SW #1487302: [upstream] failing to set mode switchdev when we have 127 vfs
# Bug SW #1601565: [JD] long time to bring up reps
#

my_dir="$(dirname "$0")"
. $my_dir/common.sh


probe_fs="/sys/class/net/$NIC/device/sriov_drivers_autoprobe"
probe=0
function disable_sriov_autoprobe() {
    if [ -e $probe_fs ]; then
        probe=`cat $probe_fs`
        echo 0 > $probe_fs
    fi
}

function restore_sriov_autoprobe() {
    if [ $probe == 1 ]; then
        echo 1 > $probe_fs
    fi
}

function cleanup() {
    restore_sriov_autoprobe
}

function test_reps() {
    local want=$1

    title "Test $want REPs"

    config_sriov 0 $NIC
    echo "Config $want VFs"
    time config_sriov $want $NIC
    unbind_vfs $NIC
    echo "Set switchdev"
    time switch_mode_switchdev $NIC

    echo "Verify"
    mac=`cat /sys/class/net/$NIC/address | tr -d :`
    count=`grep $mac /sys/class/net/*/phys_switch_id 2>/dev/null | wc -l`
    # decr 1 for pf
    let count-=1
    if [ $count != $want ]; then
        err "Found $count reps but expected $want"
    else
        echo "ok got $count reps"
    fi

    enable_legacy
    config_sriov 2 $NIC
}


trap cleanup EXIT
start_check_syndrome
disable_sriov_autoprobe

test_reps 32
if [ $TEST_FAILED -eq 0 ] || [ -e $probe_fs ]; then
    test_reps 127
else
    err "Skipping 127 reps case due to failure in prev case"
fi

echo "Cleanup"
cleanup
check_syndrome
test_done
