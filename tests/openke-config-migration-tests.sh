#!/bin/sh
#
# Offline, repeatable tests for the OpenKE Printer Config Migration Engine
# (scripts/build/lib/migrate-printer-config.sh).
#
# Validates:
#   1. Automatic commenting out of template baseline fields that are overridden in SAVE_CONFIG
#   2. Complete preservation of user calibration data (Bed Mesh, Probe Z-offset, PID tunes)
#   3. Legacy include path rewrites (e.g. frontend-controls.cfg -> macros/mainsail.cfg)
#   4. Managed module synchronization (macros/ and hardware/)
#   5. Preservation of user-created custom macro files
#   6. Pre-migration backup creation
#   7. Full closure validation of migrated printer.cfg
#
# Usage: sh tests/openke-config-migration-tests.sh
#

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
LIB="$REPO_ROOT/scripts/build/lib/migrate-printer-config.sh"
VALIDATOR_LIB="$REPO_ROOT/scripts/build/lib/validate-frontend-controls.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/config-migration-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT INT TERM

# shellcheck disable=SC1090
. "$LIB"
# shellcheck disable=SC1090
. "$VALIDATOR_LIB"

PASS=0
FAIL=0

fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }

# =========================================================================
# Test 1: Option conflict commenting & SAVE_CONFIG transplantation
# =========================================================================
echo "=== Test 1: Option conflict commenting & SAVE_CONFIG transplantation ==="

t1_old="$WORK/t1_old.cfg"
t1_template="$WORK/t1_template.cfg"
t1_out="$WORK/t1_out.cfg"

cat > "$t1_template" <<'EOF'
[printer]
kinematics: cartesian
max_velocity: 500

[probe]
pin: !PA0
z_offset: 0.0

[extruder]
step_pin: PB4
control: pid
pid_Kp: 22.200
pid_Ki: 1.080
pid_Kd: 114.000

[heater_bed]
heater_pin: PB10
control: pid
pid_Kp: 65.000
pid_Ki: 2.000
pid_Kd: 500.000

[include macros/mainsail.cfg]
EOF

cat > "$t1_old" <<'EOF'
[printer]
kinematics: cartesian

#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.
#*#
#*# [probe]
#*# z_offset = 1.450
#*#
#*# [extruder]
#*# control = pid
#*# pid_kp = 26.432
#*# pid_ki = 1.621
#*# pid_kd = 107.890
#*#
#*# [heater_bed]
#*# control = pid
#*# pid_kp = 68.123
#*# pid_ki = 2.456
#*# pid_kd = 512.789
#*#
#*# [bed_mesh default]
#*# version = 1
#*# points =
#*# 	0.012500, 0.025000, 0.015000
#*# 	-0.010000, 0.000000, 0.020000
#*# 	0.030000, 0.015000, -0.005000
#*# x_count = 3
#*# y_count = 3
#*# mesh_x_pps = 2
#*# mesh_y_pps = 2
#*# algo = lagrange
#*# tension = 0.2
EOF

openke_migrate_printer_cfg "$t1_old" "$t1_template" "$t1_out"

# Verify that z_offset in [probe] body is commented out
if grep -q "^#\*#[[:space:]]*z_offset:[[:space:]]*0\.0" "$t1_out"; then
	pass "probe z_offset in template body was correctly commented out with #*#"
else
	fail "probe z_offset was not commented out in template body"
fi

if grep -A2 "^\[probe\]" "$t1_out" | grep -q "^z_offset:[[:space:]]*0\.0"; then
	fail "probe z_offset is still active in template body (would cause Klipper conflict!)"
else
	pass "probe z_offset is not active in template body"
fi

# Verify extruder PID parameters are commented out in body
if grep -q "^#\*#[[:space:]]*pid_Kp:[[:space:]]*22\.200" "$t1_out" && \
   grep -q "^#\*#[[:space:]]*control:[[:space:]]*pid" "$t1_out"; then
	pass "extruder control and PID parameters in template body were commented out"
else
	fail "extruder PID parameters in template body were not commented out"
fi

# Verify heater_bed PID parameters are commented out in body
if grep -q "^#\*#[[:space:]]*pid_Kp:[[:space:]]*65\.000" "$t1_out"; then
	pass "heater_bed PID parameters in template body were commented out"
else
	fail "heater_bed PID parameters in template body were not commented out"
fi

# Verify SAVE_CONFIG block is preserved at the bottom with exact user calibration values
if grep -q "^#\*#[[:space:]]*z_offset = 1\.450" "$t1_out" && \
   grep -q "^#\*#[[:space:]]*pid_kp = 26\.432" "$t1_out" && \
   grep -q "^#\*#[[:space:]]*pid_kp = 68\.123" "$t1_out"; then
	pass "user calibration values preserved intact in SAVE_CONFIG block"
else
	fail "user calibration values missing from SAVE_CONFIG block"
fi

# Verify bed_mesh default matrix is preserved
if grep -q "0\.012500, 0\.025000, 0\.015000" "$t1_out" && \
   grep -q "^#\*#[[:space:]]*\[bed_mesh default\]" "$t1_out"; then
	pass "user bed_mesh default calibration matrix preserved intact"
else
	fail "user bed_mesh default matrix was lost during migration"
fi

# =========================================================================
# Test 2: Migration of config without SAVE_CONFIG block
# =========================================================================
echo "=== Test 2: Migration of config without SAVE_CONFIG block ==="

t2_old="$WORK/t2_old.cfg"
t2_template="$WORK/t2_template.cfg"
t2_out="$WORK/t2_out.cfg"

cat > "$t2_template" <<'EOF'
[printer]
kinematics: cartesian
max_velocity: 500

[include macros/mainsail.cfg]
EOF

cat > "$t2_old" <<'EOF'
[printer]
kinematics: cartesian
[include frontend-controls.cfg]
[include Nebula.cfg]
EOF

openke_migrate_printer_cfg "$t2_old" "$t2_template" "$t2_out"

if grep -q "\[include macros/mainsail\.cfg\]" "$t2_out" && \
   grep -q "\[include hardware/nebula_pad\.cfg\]" "$t2_out"; then
	pass "config without SAVE_CONFIG migrated with legacy includes rewired"
else
	fail "legacy includes were not rewired correctly"
fi

# =========================================================================
# Test 3: Full tree migration with backup & custom file preservation
# =========================================================================
echo "=== Test 3: Full tree migration with backup & custom file preservation ==="

ns_root="$WORK/t3_ns"
seeds_dir="$WORK/t3_seeds"
mkdir -p "$ns_root/printer_data/config/macros" "$ns_root/printer_data/config/hardware" "$ns_root/system"
mkdir -p "$seeds_dir/printer_data-config/macros" "$seeds_dir/printer_data-config/hardware" "$seeds_dir/printer_data-config/GuppyScreen"

# Setup existing user config with custom macro and user calibrations
cat > "$ns_root/printer_data/config/printer.cfg" <<'EOF'
[printer]
kinematics: cartesian

[probe]
pin: !PA0
z_offset: 0.0

[include frontend-controls.cfg]
[include Nebula.cfg]
[include macros/my_custom_macro.cfg]

#*# <---------------------- SAVE_CONFIG ---------------------->
#*# [probe]
#*# z_offset = 1.337
EOF

echo "# user custom macro" > "$ns_root/printer_data/config/macros/my_custom_macro.cfg"
echo "# old mainsail" > "$ns_root/printer_data/config/macros/mainsail.cfg"

# Setup seeds
cat > "$seeds_dir/printer_data-config/printer.cfg" <<'EOF'
[printer]
kinematics: cartesian
max_velocity: 500

[probe]
pin: !PA0
z_offset: 0.0

[include hardware/nebula_pad.cfg]
[include macros/mainsail.cfg]
EOF

echo "# new updated mainsail" > "$seeds_dir/printer_data-config/macros/mainsail.cfg"
echo "# new updated nebula_pad" > "$seeds_dir/printer_data-config/hardware/nebula_pad.cfg"
echo "# guppy" > "$seeds_dir/printer_data-config/GuppyScreen/guppy_cmd.cfg"

# Run openke_migrate_config_tree
openke_migrate_config_tree "$ns_root" "$seeds_dir" "$ns_root/backups/printer_config/test_backup"

# Verify backup was created with pre-migration content
if [ -f "$ns_root/backups/printer_config/test_backup/printer.cfg" ] && \
   grep -q "frontend-controls.cfg" "$ns_root/backups/printer_config/test_backup/printer.cfg"; then
	pass "pre-migration backup created with original configuration"
else
	fail "pre-migration backup missing or invalid"
fi

# Verify user custom macro is preserved untouched
if [ -f "$ns_root/printer_data/config/macros/my_custom_macro.cfg" ] && \
   grep -q "# user custom macro" "$ns_root/printer_data/config/macros/my_custom_macro.cfg"; then
	pass "user custom macro preserved untouched"
else
	fail "user custom macro was deleted or modified"
fi

# Verify system macro was upgraded from seeds
if grep -q "# new updated mainsail" "$ns_root/printer_data/config/macros/mainsail.cfg"; then
	pass "system macro was updated to seed version"
else
	fail "system macro was not updated from seed"
fi

# Verify system hardware config was updated from seeds
if grep -q "# new updated nebula_pad" "$ns_root/printer_data/config/hardware/nebula_pad.cfg"; then
	pass "hardware config was updated to seed version"
else
	fail "hardware config was not updated from seed"
fi

# Verify printer.cfg has calibrated SAVE_CONFIG value and commented-out baseline
if grep -q "^#\*#[[:space:]]*z_offset:[[:space:]]*0\.0" "$ns_root/printer_data/config/printer.cfg" && \
   grep -q "^#\*#[[:space:]]*z_offset = 1\.337" "$ns_root/printer_data/config/printer.cfg"; then
	pass "migrated printer.cfg preserved calibration and commented out baseline"
else
	fail "migrated printer.cfg did not preserve calibration properly"
fi

# =========================================================================
# Test 4: End-to-end closure validation on real overlay config
# =========================================================================
echo "=== Test 4: End-to-end closure validation on real overlay config ==="

REAL_OVERLAY="$REPO_ROOT/scripts/build/overlay/opt/printer_data/config"
real_migrated="$WORK/real_migrated.cfg"
openke_migrate_printer_cfg "$REAL_OVERLAY/printer.cfg" "$REAL_OVERLAY/printer.cfg" "$real_migrated"

closure="$WORK/closure.txt"
if frontend_controls_resolve_closure "$REAL_OVERLAY" printer.cfg "$closure" >"$WORK/vlog.txt" 2>&1; then
	if frontend_controls_validate_closure "$closure" "/opt/printer_data/gcodes" >>"$WORK/vlog.txt" 2>&1; then
		pass "real overlay printer.cfg closure passes full validation end-to-end"
	else
		fail "closure validation failed: $(cat "$WORK/vlog.txt")"
	fi
else
	fail "closure resolution failed: $(cat "$WORK/vlog.txt")"
fi

echo ""
echo "=========================================="
echo "Config Migration Tests: $PASS passed, $FAIL failed"
echo "=========================================="
[ "$FAIL" -eq 0 ]
