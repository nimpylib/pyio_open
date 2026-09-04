#!/bin/sh
set -eu

backend=${1:?usage: test_stdin_readline.sh node|deno}
test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(dirname -- "$test_dir")
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM
output="$tmp_dir/test_stdio.js"

case "$backend" in
  node)
    nim js -d:nodejs -d:testStdinReadLine -o:"$output" "$test_dir/test_stdio.nim"
    runtime=node
    ;;
  deno)
    nim js -d:deno -d:testStdinReadLine -o:"$output" "$test_dir/test_stdio.nim"
    runtime=deno
    ;;
  *)
    printf '%s\n' "unknown backend: $backend" >&2
    exit 2
    ;;
esac

cd "$project_dir"
python3 - "$runtime" "$output" <<'PY'
import os
import pty
import select
import sys
import time

runtime, program = sys.argv[1:]
command = [runtime, program]
if runtime == "deno":
    command = [runtime, "run", "--allow-read", "--allow-write", program]

pid, master = pty.fork()
if pid == 0:
    os.execvp(command[0], command)

transcript = bytearray()

def read_until(marker, timeout=10):
    deadline = time.monotonic() + timeout
    marker = marker.encode()
    while marker not in transcript:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError(f"timed out waiting for {marker!r}")
        ready, _, _ = select.select([master], [], [], remaining)
        if not ready:
            continue
        try:
            chunk = os.read(master, 4096)
        except OSError:
            chunk = b""
        if not chunk:
            raise RuntimeError(f"process exited before {marker!r}")
        transcript.extend(chunk)
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()

def wait_for_exit(timeout=10):
    deadline = time.monotonic() + timeout
    while True:
        child, status = os.waitpid(pid, os.WNOHANG)
        if child == pid:
            return status
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("timed out waiting for process exit")
        ready, _, _ = select.select([master], [], [], min(remaining, 0.1))
        if ready:
            try:
                chunk = os.read(master, 4096)
            except OSError:
                chunk = b""
            if chunk:
                transcript.extend(chunk)
                sys.stdout.buffer.write(chunk)
                sys.stdout.buffer.flush()

try:
    for marker, line in (
        ("stdin-ready-1", b"first\n"),
        ("stdin-ready-2", b"second\n"),
        ("stdin-ready-3", b"last\n"),
    ):
        read_until(marker)
        os.write(master, line)
    read_until("stdin-ready-eof")
    os.write(master, b"\x04")
    read_until("[OK] read standard input lines")
    status = wait_for_exit()
finally:
    os.close(master)

if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
    raise SystemExit(os.waitstatus_to_exitcode(status))
PY
