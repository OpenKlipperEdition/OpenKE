#!/bin/bash
#
# Offline, repeatable verification tests for OpenKE App Store & UI Switcher.
#
# Usage: bash tests/openke-appstore-tests.sh
#

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
OVERLAY="$REPO_ROOT/scripts/build/overlay"
OPENKE_APP="$OVERLAY/usr/bin/openke-app"
MANIFEST="$REPO_ROOT/manifests/apps.json"
S01="$OVERLAY/etc/init.d/S01persistent-datastore"
S58="$OVERLAY/etc/init.d/S58guppyscreen"
NGINX_CONF="$OVERLAY/etc/nginx/nginx.conf"

PASS=0
FAIL=0

pass() {
	echo "PASS: $1"
	PASS=$((PASS + 1))
}

fail() {
	echo "FAIL: $1"
	FAIL=$((FAIL + 1))
}

TEST_SANDBOX=$(mktemp -d /tmp/openke-appstore-test-XXXXXX)
trap 'rm -rf "$TEST_SANDBOX"' EXIT

export OPENKE_STATE_DIR="$TEST_SANDBOX/state"
export OPENKE_APPS_DIR="$TEST_SANDBOX/state/apps"
export OPENKE_WEB_ROOT_LINK="$TEST_SANDBOX/web-root"
export OPENKE_CATALOG_FILE="$MANIFEST"

mkdir -p "$OPENKE_STATE_DIR" "$OPENKE_APPS_DIR"

echo "=== Test 1: App Store Manifest Catalog Integrity ==="
[ -f "$MANIFEST" ] || { fail "$MANIFEST missing"; exit 1; }
python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
assert "apps" in data, "manifest missing apps list"
assert len(data["apps"]) >= 5, "manifest has fewer than 5 apps"
categories = {a["category"] for a in data["apps"]}
assert {"web_ui", "touch_ui", "plugin"}.issubset(categories), f"missing core categories in {categories}"

ids = [a["id"] for a in data["apps"]]
assert len(ids) == len(set(ids)), "duplicate app ids in manifest"
assert "mainsail" in ids, "mainsail missing from catalog"
assert "fluidd" in ids, "fluidd missing from catalog"
assert "guppyscreen" in ids, "guppyscreen missing from catalog"
assert "helixscreen" in ids, "helixscreen missing from catalog"
' "$MANIFEST" && pass "apps.json manifest schema and required applications validated" || fail "apps.json validation failed"

echo "=== Test 2: CLI Syntax & Output Modes ==="
[ -x "$OPENKE_APP" ] || { fail "$OPENKE_APP missing or not executable"; exit 1; }

# Test list table output
list_out=$(python3 "$OPENKE_APP" list)
if echo "$list_out" | grep -q "mainsail" && echo "$list_out" | grep -q "fluidd" && echo "$list_out" | grep -q "helixscreen"; then
	pass "openke-app list renders tabular catalog correctly"
else
	fail "openke-app list output missing expected app entries"
fi

# Test list JSON output
json_out=$(python3 "$OPENKE_APP" list --json)
python3 -c '
import json, sys
data = json.loads(sys.argv[1])
assert isinstance(data, list)
assert any(a["id"] == "fluidd" for a in data)
assert any(a["id"] == "helixscreen" for a in data)
' "$json_out" && pass "openke-app list --json returns valid structured JSON" || fail "openke-app list --json failed"

# Test category filter
cat_out=$(python3 "$OPENKE_APP" list --category web_ui --json)
python3 -c '
import json, sys
data = json.loads(sys.argv[1])
assert all(a["category"] == "web_ui" for a in data)
assert len(data) >= 2
' "$cat_out" && pass "openke-app list --category filters by category" || fail "openke-app list --category filter failed"

# Test status command
status_out=$(python3 "$OPENKE_APP" status)
if echo "$status_out" | grep -q "Active Web UI:" && echo "$status_out" | grep -q "Active Touch UI:"; then
	pass "openke-app status displays current configuration"
else
	fail "openke-app status output missing key fields"
fi

# Test update command with local file URL
mock_remote_catalog="$TEST_SANDBOX/mock_remote_catalog.json"
cp "$MANIFEST" "$mock_remote_catalog"
update_out=$(python3 "$OPENKE_APP" update --url "file://$mock_remote_catalog")
if echo "$update_out" | grep -q "Updated catalog" && [ -f "$OPENKE_STATE_DIR/apps.json" ]; then
	pass "openke-app update successfully refreshed catalog from URL"
else
	fail "openke-app update failed: $update_out"
fi

echo "=== Test 3: Web UI Switching & Dynamic Symlink Management ==="
# Create mock mainsail directory
mkdir -p "$TEST_SANDBOX/usr_share_mainsail"
echo "<h1>Mainsail</h1>" > "$TEST_SANDBOX/usr_share_mainsail/index.html"

# Default state
python3 "$OPENKE_APP" set-active-web mainsail
if [ -L "$OPENKE_WEB_ROOT_LINK" ] && [ "$(readlink "$OPENKE_WEB_ROOT_LINK")" = "/usr/share/mainsail" ]; then
	pass "set-active-web mainsail creates symlink to /usr/share/mainsail"
else
	fail "set-active-web mainsail failed to create correct symlink"
fi

if [ "$(cat "$OPENKE_STATE_DIR/active_web_ui")" = "mainsail" ]; then
	pass "active_web_ui persistent file set to mainsail"
else
	fail "active_web_ui persistent file not set to mainsail"
fi

# Attempt to switch to uninstalled fluidd should fail
if python3 "$OPENKE_APP" set-active-web fluidd >/dev/null 2>&1; then
	fail "set-active-web fluidd should fail when not installed"
else
	pass "set-active-web fluidd correctly rejected when not installed"
fi

# Mock install fluidd
mkdir -p "$OPENKE_APPS_DIR/fluidd"
echo "<h1>Fluidd</h1>" > "$OPENKE_APPS_DIR/fluidd/index.html"

python3 "$OPENKE_APP" set-active-web fluidd
if [ -L "$OPENKE_WEB_ROOT_LINK" ] && [ "$(readlink "$OPENKE_WEB_ROOT_LINK")" = "$OPENKE_APPS_DIR/fluidd" ]; then
	pass "set-active-web fluidd points symlink to $OPENKE_APPS_DIR/fluidd"
else
	fail "set-active-web fluidd symlink incorrect: $(readlink "$OPENKE_WEB_ROOT_LINK" 2>/dev/null || echo 'none')"
fi

if [ "$(cat "$OPENKE_STATE_DIR/active_web_ui")" = "fluidd" ]; then
	pass "active_web_ui persistent file updated to fluidd"
else
	fail "active_web_ui not updated to fluidd"
fi

# Switch back to mainsail
python3 "$OPENKE_APP" set-active-web mainsail
if [ "$(readlink "$OPENKE_WEB_ROOT_LINK")" = "/usr/share/mainsail" ]; then
	pass "set-active-web switches back to mainsail"
else
	fail "set-active-web mainsail switch back failed"
fi

echo "=== Test 4: Touchscreen UI Switching & Safety Checks ==="
# Default state
python3 "$OPENKE_APP" set-active-touch guppyscreen
if [ "$(cat "$OPENKE_STATE_DIR/active_touch_ui")" = "guppyscreen" ]; then
	pass "set-active-touch guppyscreen sets active_touch_ui to guppyscreen"
else
	fail "set-active-touch guppyscreen failed"
fi

# Attempt switch to uninstalled helixscreen should fail
if python3 "$OPENKE_APP" set-active-touch helixscreen >/dev/null 2>&1; then
	fail "set-active-touch helixscreen should fail when binary is absent"
else
	pass "set-active-touch helixscreen rejected when binary is absent"
fi

# Mock install helixscreen binary
mkdir -p "$OPENKE_APPS_DIR/helixscreen/bin"
touch "$OPENKE_APPS_DIR/helixscreen/bin/helix-screen"
chmod +x "$OPENKE_APPS_DIR/helixscreen/bin/helix-screen"

python3 "$OPENKE_APP" set-active-touch helixscreen
if [ "$(cat "$OPENKE_STATE_DIR/active_touch_ui")" = "helixscreen" ]; then
	pass "set-active-touch helixscreen successfully set active_touch_ui to helixscreen"
else
	fail "set-active-touch helixscreen failed"
fi

echo "=== Test 5: Removal & Safe Automatic Fallback ==="
# Active web UI fallback
python3 "$OPENKE_APP" set-active-web fluidd
python3 "$OPENKE_APP" remove fluidd
if [ ! -d "$OPENKE_APPS_DIR/fluidd" ]; then
	pass "openke-app remove fluidd uninstalled the package directory"
else
	fail "openke-app remove fluidd left directory behind"
fi

if [ "$(cat "$OPENKE_STATE_DIR/active_web_ui")" = "mainsail" ] && [ "$(readlink "$OPENKE_WEB_ROOT_LINK")" = "/usr/share/mainsail" ]; then
	pass "removing active Web UI automatically fallback to Mainsail"
else
	fail "removing active Web UI failed to fallback to Mainsail"
fi

# Active touch UI fallback
python3 "$OPENKE_APP" remove helixscreen
if [ ! -d "$OPENKE_APPS_DIR/helixscreen" ]; then
	pass "openke-app remove helixscreen uninstalled the package directory"
else
	fail "openke-app remove helixscreen left directory behind"
fi

if [ "$(cat "$OPENKE_STATE_DIR/active_touch_ui")" = "guppyscreen" ]; then
	pass "removing active Touch UI automatically fallback to GuppyScreen"
else
	fail "removing active Touch UI failed to fallback to GuppyScreen"
fi

# Builtin removal protection
if python3 "$OPENKE_APP" remove mainsail >/dev/null 2>&1; then
	fail "openke-app remove mainsail should be rejected as builtin"
else
	pass "openke-app remove mainsail rejected for builtin component"
fi

if python3 "$OPENKE_APP" remove guppyscreen >/dev/null 2>&1; then
	fail "openke-app remove guppyscreen should be rejected as builtin"
else
	pass "openke-app remove guppyscreen rejected for builtin component"
fi

echo "=== Test 6: System Init & Nginx Configuration Verification ==="
# S01persistent-datastore assertions
if grep -q 'mkdir -p "$DATA_ROOT/apps"' "$S01" && grep -q 'openke-web-root' "$S01"; then
	pass "S01persistent-datastore initializes /usr/data/openke/apps and /var/run/openke-web-root link"
else
	fail "S01persistent-datastore missing apps or web root initialization"
fi

# nginx.conf assertions
if grep -q "root /var/run/openke-web-root;" "$NGINX_CONF"; then
	pass "nginx.conf uses dynamic web root /var/run/openke-web-root"
else
	fail "nginx.conf not pointing to /var/run/openke-web-root"
fi

# S58guppyscreen assertions
if grep -q "get_touch_binary" "$S58" && grep -q "active_touch_ui" "$S58"; then
	pass "S58guppyscreen supports dynamic touchscreen UI selection with fallback"
else
	fail "S58guppyscreen missing dynamic touch UI selection"
fi

echo ""
echo "=========================================="
echo "OpenKE App Store Tests: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ]
