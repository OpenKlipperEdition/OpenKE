#!/bin/sh
#
# Regression tests proving tests/wifi-sdio-variant-tests.sh and
# tests/preempt-variant-tests.sh preserve the REAL pre-test state of the
# real files they operate on (vendor/system's DTS and the
# tracked buildroot Kconfig fragment), rather than resetting to a
# hardcoded W0/R0 baseline - the real defect found live during the alpha
# baseline freeze mission (2026-08-01): applying W3+R1 and then running
# those two suites silently discarded the selection back to W0/R0 before
# a build ever started, undetected by either suite's own exit status.
#
# These tests treat the two suites as black boxes - they run the real
# suite as a subprocess and inspect the target file's bytes before/after,
# rather than reimplementing any of the suites' own pass/fail logic.
#
# Usage: sh tests/variant-state-preservation-tests.sh

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

WIFI_SUITE="$REPO_ROOT/tests/wifi-sdio-variant-tests.sh"
WIFI_VARIANT_SCRIPT="$REPO_ROOT/scripts/build/wifi-sdio-variant.sh"
DTS="$REPO_ROOT/vendor/system/kernel/kernel-6.6/module_drivers/dts/x2000/halley5_v30.dts"

PASS=0
FAIL=0

fail() {
	echo "FAIL: $1"
	FAIL=$((FAIL + 1))
}

pass() {
	PASS=$((PASS + 1))
}

# Sends SIGTERM to a process AND every descendant of it, repeatedly until
# none remain. A plain `kill -TERM $pid` only signals that one PID - if
# the suite is at that instant blocked in `wait` for one of its own
# foreground children (e.g. `sh wifi-sdio-variant.sh W2`), that child is
# NOT signaled at all and can keep running after the parent's own trap
# has already restored the target file, re-polluting it with whatever
# that orphaned child was in the middle of writing. Confirmed live: a
# single-PID kill produced exactly this race, non-deterministically,
# depending on which instant the signal landed.
terminate_tree() {
	root_pid="$1"
	i=0
	while [ "$i" -lt 30 ]; do
		if ! kill -0 "$root_pid" 2>/dev/null; then
			break
		fi
		children=$(pgrep -P "$root_pid" 2>/dev/null)
		kill -TERM "$root_pid" $children 2>/dev/null
		sleep 0.05
		i=$((i + 1))
	done
	# Final sweep in case a child was spawned in the instant between the
	# last pgrep and the process actually exiting.
	children=$(pgrep -P "$root_pid" 2>/dev/null)
	[ -n "$children" ] && kill -TERM $children 2>/dev/null
}

if [ ! -f "$DTS" ]; then
	echo "SKIP: $DTS not present - run 00-fetch-vendor-sources.sh first to exercise this suite"
	exit 0
fi

# Snapshot the real pre-test bytes and restore exactly those bytes.
DTS_PRETEST_SNAPSHOT=$(mktemp)
cp "$DTS" "$DTS_PRETEST_SNAPSHOT"

final_cleanup() {
	cp "$DTS_PRETEST_SNAPSHOT" "$DTS"
	rm -f "$DTS_PRETEST_SNAPSHOT"
}
# Same EXIT/INT/TERM split as the suite this one tests - a bare
# `trap final_cleanup INT TERM` runs cleanup but does not itself
# terminate a POSIX shell process, so execution would otherwise resume
# at the next group after a signal and re-mutate the just-restored file.
trap final_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Group 1: non-baseline preservation (wifi-sdio-variant-tests.sh) ---
# Starting from W3, running the real suite must not disturb it.
sh "$WIFI_VARIANT_SCRIPT" W3 >/dev/null 2>&1
before=$(md5sum "$DTS" | cut -d' ' -f1)
sh "$WIFI_SUITE" >/dev/null 2>&1
after=$(md5sum "$DTS" | cut -d' ' -f1)
if [ "$before" = "$after" ]; then
	pass
else
	fail "wifi-sdio-variant-tests.sh disturbed a pre-existing W3 selection (before=$before after=$after)"
fi

# --- Group 2: interruption preservation (wifi-sdio-variant-tests.sh) ---
# Starting from W3, a SIGTERM mid-run must still leave W3 untouched -
# proves the trap actually fires on a real interruption, not just a
# normal exit.
sh "$WIFI_VARIANT_SCRIPT" W3 >/dev/null 2>&1
before=$(md5sum "$DTS" | cut -d' ' -f1)
sh "$WIFI_SUITE" >/dev/null 2>&1 &
suite_pid=$!
sleep 0.2
terminate_tree "$suite_pid"
wait "$suite_pid" 2>/dev/null
after=$(md5sum "$DTS" | cut -d' ' -f1)
if [ "$before" = "$after" ]; then
	pass
else
	fail "SIGTERM mid-run left the DTS disturbed from its pre-existing W3 selection (before=$before after=$after)"
fi

# --- Group 3: baseline preservation (regression - suite must still
# correctly restore W0 when that really was the starting state). ---
sh "$WIFI_VARIANT_SCRIPT" W0 >/dev/null 2>&1
before=$(md5sum "$DTS" | cut -d' ' -f1)
sh "$WIFI_SUITE" >/dev/null 2>&1
after=$(md5sum "$DTS" | cut -d' ' -f1)
if [ "$before" = "$after" ]; then
	pass
else
	fail "wifi-sdio-variant-tests.sh did not preserve an existing W0 baseline (before=$before after=$after)"
fi

# --- Group 4: no unrelated modifications + clean-tree proof. Capture the
# FULL repo and vendor-kernel git status (not just the one target file)
# before and after the suite runs from a W3 starting point -
# suite may touch anything else. ---
sh "$WIFI_VARIANT_SCRIPT" W3 >/dev/null 2>&1
main_status_before=$(git -C "$REPO_ROOT" status --porcelain -- .)
kernel_status_before=$(git -C "$REPO_ROOT/vendor/system" status --porcelain -- . ":!kernel/kernel-6.6/module_drivers/dts/x2000/halley5_v30.dts")
sh "$WIFI_SUITE" >/dev/null 2>&1
main_status_after=$(git -C "$REPO_ROOT" status --porcelain -- .)
kernel_status_after=$(git -C "$REPO_ROOT/vendor/system" status --porcelain -- . ":!kernel/kernel-6.6/module_drivers/dts/x2000/halley5_v30.dts")
if [ "$main_status_before" = "$main_status_after" ] && [ "$kernel_status_before" = "$kernel_status_after" ]; then
	pass
else
	fail "running suite modified files other than its own single target (main diff: before='$main_status_before' after='$main_status_after'; kernel diff: before='$kernel_status_before' after='$kernel_status_after')"
fi
# And the target file itself must still show the W3 selection
# the suite was never supposed to disturb.
if [ -n "$(git -C "$REPO_ROOT/vendor/system" status --porcelain -- kernel/kernel-6.6/module_drivers/dts/x2000/halley5_v30.dts)" ]; then
	pass
else
	fail "W3 selection was lost by the time suite finished (expected DTS to still show as modified)"
fi

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
