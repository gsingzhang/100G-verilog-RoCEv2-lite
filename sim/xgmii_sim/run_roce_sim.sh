#!/usr/bin/env bash
# RoCE-over-sim test runner: VCS sim + tap0 + SoftRoCE (rxe) + feroce-rs receiver.
# See RoCE_TEST.md for background. sudo steps prompt for a password.
set -uo pipefail

SIM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FEROCE_DIR=/home/gxzhang/gx/prj/feroce-rs
RDMACORE61="$FEROCE_DIR/.rdmacore61/usr/lib64"   # baseos libibverbs 61.0 (see RoCE_TEST.md)
STACK_IP=22.1.212.10
HOST_IP=22.1.212.21
RECV_LOG="$SIM_DIR/feroce_recv.log"
RECV_PID="$SIM_DIR/feroce_recv.pid"
SIMV_PID="$SIM_DIR/simv.pid"
RECV_CM_PORT=48879          # opened in firewalld; ctrl uses 17185 to avoid the clash
BUF_SIZE=16384

export LD_LIBRARY_PATH="$RDMACORE61${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

usage() {
    cat <<EOF
Usage: $0 <command>

  setup      tap0 IP/MTU, rxe_tap0, firewalld ports (sudo; tapdev already running)
  build      make comp SIMULATOR=VCS
  start      start tapdev + simv + feroce receiver, wait for CM handshake
  trigger    send tx-meta to start the FPGA data generator (QPN auto-detected)
  wave       run sim with FSDB dump, trigger transfer, stop at window end
  status     show processes and receiver stats
  stop       graceful stop: receiver (CloseQP) + simv + tapdev
  teardown   remove rxe_tap0 and tap0 (sudo)

Example:
  $0 setup && $0 build && $0 start && $0 trigger --n-transfers 1000
  $0 wave --n-transfers 1000          # dump 50000us sim time to wave.fsdb
  WAVE_TIME=500us $0 wave --write --n-transfers 100
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }

is_running() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

cmd_setup() {
    ip link show tap0 >/dev/null 2>&1 || die "tap0 missing - start tapdev first (see '$0 start')"
    sudo ip addr replace "$HOST_IP/8" dev tap0
    sudo ip link set tap0 mtu 4200 up
    if ! rdma link show 2>/dev/null | grep -qw rxe_tap0; then
        sudo rdma link add rxe_tap0 type rxe netdev tap0
    fi
    sudo firewall-cmd --add-port=4791/udp --add-port=48879/udp 2>/dev/null || true
    echo "tap0: $(ip -4 addr show tap0 | grep -oP 'inet \K[0-9./]+') mtu $(ip link show tap0 | grep -oP 'mtu \K[0-9]+')"
    rdma link show | grep rxe_tap0 || true
}

cmd_build() {
    make -C "$SIM_DIR" comp SIMULATOR=VCS
}

cmd_start() {
    [ -x "$SIM_DIR/simv" ] || die "simv not built - run '$0 build'"
    [ -x "$FEROCE_DIR/target/release/feroce-cli" ] || die "feroce-cli not built"
    [ -d "$RDMACORE61" ] || die "$RDMACORE61 missing (baseos libibverbs extract, see RoCE_TEST.md)"

    if ! is_running "$SIM_DIR/tapdev.pid"; then
        sudo -b "$SIM_DIR/tapdev" tap0
        for i in $(seq 1 20); do ip link show tap0 >/dev/null 2>&1 && break; sleep 0.5; done
        ip link show tap0 >/dev/null 2>&1 || die "tap0 did not appear"
        pgrep -f "$SIM_DIR/tapdev" | head -1 > "$SIM_DIR/tapdev.pid"
    fi
    cmd_setup

    if ! is_running "$SIMV_PID"; then
        (cd "$SIM_DIR" && ./simv -l simv.log > simv.stdout.log 2>&1 & echo $! > "$SIMV_PID")
        # wait until the sim actually answers (avoid the feroce 4s-retry race)
        echo -n "waiting for simv ready"
        for i in $(seq 1 30); do
            ping -I tap0 -c 1 -W 1 "$STACK_IP" >/dev/null 2>&1 && break
            is_running "$SIMV_PID" || die "simv failed to start (see $SIM_DIR/simv.stdout.log)"
            sleep 1; echo -n .
        done
        echo
        ping -I tap0 -c 1 -W 1 "$STACK_IP" >/dev/null 2>&1 || die "simv not answering pings"
    fi

    if ! is_running "$RECV_PID"; then
        (cd "$FEROCE_DIR" && ./target/release/feroce-cli recv \
            --rdma-device rxe_tap0 --gid-index 1 --cm-port "$RECV_CM_PORT" \
            --buf-size "$BUF_SIZE" --num-buf 128 --active \
            --remote-addr "$STACK_IP" --remote-port 0x4321 --num-streams 1 \
            > "$RECV_LOG" 2>&1 & echo $! > "$RECV_PID")
    fi

    echo -n "waiting for CM handshake"
    for i in $(seq 1 30); do
        grep -q 'connected to remote QP' "$RECV_LOG" 2>/dev/null && break
        sleep 1; echo -n .
    done
    echo
    grep 'connected to remote QP' "$RECV_LOG" | tail -1 || {
        tail -5 "$RECV_LOG"; die "handshake failed - see $RECV_LOG"
    }
    QPN=$(grep -oP 'connected to remote QP \K[0-9]+' "$RECV_LOG" | tail -1)
    echo "Ready. Start the transfer with:  $0 trigger --n-transfers 1000"
}

cmd_trigger() {
    is_running "$RECV_PID" || die "receiver not running - run '$0 start'"
    QPN=$(grep -oP 'connected to remote QP \K[0-9]+' "$RECV_LOG" | tail -1)
    [ -n "${QPN:-}" ] || die "no QPN found in $RECV_LOG"
    (cd "$FEROCE_DIR" && ./target/release/feroce-cli ctrl --cm-port 0x4321 \
        --remote-addr "$STACK_IP" --remote-port 0x4321 \
        tx-meta --rem-qpn "$QPN" --length "$BUF_SIZE" "$@")
}

tapdev_pid() { is_running "$SIM_DIR/tapdev.pid" && cat "$SIM_DIR/tapdev.pid" || pgrep -x tapdev | head -1; }
simv_pid()   { is_running "$SIMV_PID" && cat "$SIMV_PID" || pgrep -x simv | head -1; }
recv_pid()   { is_running "$RECV_PID" && cat "$RECV_PID" || pgrep -f 'feroce-cli recv' | head -1; }

cmd_wave() {
    # extra args go to tx-meta (e.g. --n-transfers 1000 --write)
    WAVE_TIME="${WAVE_TIME:-50000us}"
    [ -x "$SIM_DIR/simv" ] || die "simv not built - run '$0 build'"

    # stop previous recv/simv, keep tapdev
    RP=$(recv_pid || true); [ -n "$RP" ] && kill "$RP" 2>/dev/null
    sleep 1
    SP=$(simv_pid || true); [ -n "$SP" ] && kill "$SP" 2>/dev/null
    [ -n "$(tapdev_pid || true)" ] || { sudo -b "$SIM_DIR/tapdev" tap0; sleep 2; }
    cmd_setup

    rm -f "$SIM_DIR/wave.fsdb"
    # NOTE: no -aggregates - packed-MDA dumping breaks the CM datapath in the sim
    printf 'dump -file wave.fsdb -type FSDB\ndump -add {tb.top0} -fid FSDB0 -depth 0\nrun %s\ndump -close\nquit\n' "$WAVE_TIME" > "$SIM_DIR/dump.tcl"
    # -no_save: the ASLR re-exec segfaults during FSDB teardown at exit
    (cd "$SIM_DIR" && ./simv -no_save -ucli -i dump.tcl > simv.stdout.log 2>&1 & echo $! > "$SIMV_PID")

    # feroce gives up after ~4s of retries - don't start it until the sim is
    # really running (VCS init + FSDB traverse take several seconds)
    echo -n "waiting for simv ready"
    for i in $(seq 1 90); do
        grep -q 'ucli% run ' "$SIM_DIR/simv.stdout.log" 2>/dev/null && break
        is_running "$SIMV_PID" || die "simv died during startup - see $SIM_DIR/simv.stdout.log"
        sleep 1; echo -n .
    done
    echo
    grep -q 'ucli% run ' "$SIM_DIR/simv.stdout.log" || die "simv not ready in 90s - see $SIM_DIR/simv.stdout.log"
    sleep 2   # let the tb reach time 0 and reset the shm ring counters

    if ! is_running "$RECV_PID"; then
        (cd "$FEROCE_DIR" && ./target/release/feroce-cli recv \
            --rdma-device rxe_tap0 --gid-index 1 --cm-port "$RECV_CM_PORT" \
            --buf-size "$BUF_SIZE" --num-buf 128 --active \
            --remote-addr "$STACK_IP" --remote-port 0x4321 --num-streams 1 \
            > "$RECV_LOG" 2>&1 & echo $! > "$RECV_PID")
    fi
    echo -n "waiting for CM handshake"
    for i in $(seq 1 60); do
        grep -q 'connected to remote QP' "$RECV_LOG" 2>/dev/null && break
        sleep 1; echo -n .
    done
    echo
    grep 'connected to remote QP' "$RECV_LOG" | tail -1 || die "handshake failed - see $RECV_LOG"
    QPN=$(grep -oP 'connected to remote QP \K[0-9]+' "$RECV_LOG" | tail -1)

    echo "dumping $WAVE_TIME of sim time to wave.fsdb, triggering data generator (QPN $QPN)"
    (cd "$FEROCE_DIR" && ./target/release/feroce-cli ctrl --cm-port 0x4321 \
        --remote-addr "$STACK_IP" --remote-port 0x4321 \
        tx-meta --rem-qpn "$QPN" --length "$BUF_SIZE" "$@")

    while is_running "$SIMV_PID"; do sleep 5; done
    echo "dump done: $SIM_DIR/wave.fsdb  ($(du -h "$SIM_DIR/wave.fsdb" | cut -f1))"
    echo "view with:  verdi -ssf $SIM_DIR/wave.fsdb &   (or nWave)"
}

cmd_status() {
    echo "tapdev:  $(tapdev_pid || echo not running)"
    echo "simv:    $(simv_pid || echo not running)"
    echo "recv:    $(recv_pid || echo not running)"
    [ -f "$RECV_LOG" ] && tail -1 "$RECV_LOG"
}

cmd_stop() {
    RP=$(recv_pid || true)
    if [ -n "$RP" ]; then
        kill "$RP" && echo "receiver SIGTERM sent (CloseQP on exit)"
        for i in $(seq 1 10); do kill -0 "$RP" 2>/dev/null || break; sleep 1; done
        kill -0 "$RP" 2>/dev/null && kill -9 "$RP"
    fi
    SP=$(simv_pid || true)
    [ -n "$SP" ] && kill "$SP"
    TP=$(tapdev_pid || true)
    [ -n "$TP" ] && kill "$TP" && echo "tapdev stopped"
    rm -f "$RECV_PID" "$SIMV_PID" "$SIM_DIR/tapdev.pid"
}

cmd_teardown() {
    cmd_stop || true
    sudo rdma link del rxe_tap0 2>/dev/null || true
    sudo ip link del tap0 2>/dev/null || true
    echo "rxe_tap0 and tap0 removed"
}

case "${1:-}" in
    setup)     cmd_setup ;;
    build)     cmd_build ;;
    start)     cmd_start ;;
    trigger)   shift; cmd_trigger "$@" ;;
    wave)      shift; cmd_wave "$@" ;;
    status)    cmd_status ;;
    stop)      cmd_stop ;;
    teardown)  cmd_teardown ;;
    *)         usage ;;
esac
