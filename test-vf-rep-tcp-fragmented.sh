#!/bin/bash
#
# Bug SW #1333837: In inline-mode transport UDP fragments from VF are dropped
#

NIC=${1:-ens5f0}
VF=${2:-ens5f2}
REP=${3:-ens5f0_0}
my_dir="$(dirname "$0")"
. $my_dir/common.sh

enable_switchdev_if_no_rep $REP
bind_vfs

function cleanup() {
    ip netns del ns0 2> /dev/null
    ip add flush dev $REP
}

function start_tcpdump() {
    tdtmpfile=/tmp/$$.pcap
    rm -f $tdtmpfile
    tcpdump -nnepi $REP tcp -c 30 -w $tdtmpfile &
    tdpid=$!
    sleep 0.5
}

function stop_tcpdump() {
    kill $tdpid 2>/dev/null
    if [ ! -f $tdtmpfile ]; then
        err "Missing tcpdump output"
    fi
}

function test_frags() {
    # match fragmented packets (not first)
    count=`tcpdump -nnr $tdtmpfile 'ip[6]!=0 && ip[7]!=0' | wc -l`

    if [[ $count = 0 ]]; then
        err "No fragmented packets"
        tcpdump -nnr $tdtmpfile
    else
        success
    fi
}

function config_ipv4() {
    title "Config IPv4"
    cleanup
    IP1="7.7.7.1"
    IP2="7.7.7.2"
    ifconfig $REP $IP1/24 up
    ip netns add ns0
    ip link set $VF netns ns0
    ip netns exec ns0 ifconfig $VF $IP2/24 up
    _test="ipv4"
    iperf_ext=""
}

function run_cases() {

    title "Test fragmented packets REP->VF"
    start_tcpdump
    /usr/bin/python -c 'from scapy.all import * ; send( fragment(IP(dst="7.7.7.2")/TCP()/("X"*60000)) )'
    stop_tcpdump
    title " - verify with tcpdump"
    test_frags

    title "Test fragmented packets VF->REP"
    start_tcpdump
    ip netns exec ns0 /usr/bin/python -c 'from scapy.all import * ; send( fragment(IP(dst="7.7.7.1")/TCP()/("X"*60000)) )'
    stop_tcpdump
    title " - verify with tcpdump"
    test_frags
}


config_ipv4
run_cases

cleanup
test_done