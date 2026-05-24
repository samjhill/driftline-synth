#!/usr/bin/env bash
# Brutal pre-boot SD validation — exit nonzero if anything is wrong.
# Run AFTER: wipe_cloud_init + build_factory_sd_mac.sh
#
#   sudo ./scripts/wipe_cloud_init_mac.sh
#   ./scripts/build_factory_sd_mac.sh /Volumes/bootfs
#   ./scripts/check_sd_boot_mac.sh /Volumes/bootfs
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXPECTED_USER="${EXPECTED_PI_USER:-sam}"
FAILURES=0
BOOT=""

fail() {
  echo ""
  echo "FAIL: $*"
  echo "FIX:  ${2:-Re-run: sudo ./scripts/wipe_cloud_init_mac.sh && ./scripts/build_factory_sd_mac.sh /Volumes/bootfs}"
  FAILURES=$((FAILURES + 1))
}

pass() {
  echo "OK:   $*"
}

section() {
  echo ""
  echo "========== $* =========="
}

resolve_boot() {
  BOOT="${1:-}"
  if [[ -z "$BOOT" ]]; then
    for v in /Volumes/bootfs /Volumes/boot; do
      if [[ -d "$v" ]]; then
        BOOT="$v"
        break
      fi
    done
  fi
  if [[ ! -d "$BOOT" ]]; then
    echo "ERROR: SD boot volume not mounted."
    echo "Insert the card (Pi powered off) or pass: $0 /Volumes/bootfs"
    exit 1
  fi
}

file_must_exist() {
  local path="$1" fix_msg="${2:-}"
  if [[ ! -e "$path" ]]; then
    fail "Missing file: $path" "${fix_msg:-./scripts/build_factory_sd_mac.sh $BOOT}"
    return 1
  fi
  pass "Found $(basename "$path")"
  return 0
}

grep_must() {
  local file="$1" pattern="$2" label="$3"
  if ! grep -qE "$pattern" "$file" 2>/dev/null; then
    fail "$label — pattern not in $(basename "$file"): $pattern"
    return 1
  fi
  pass "$label"
  return 0
}

grep_must_not() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    fail "$label — forbidden in $(basename "$file"): $pattern"
    return 1
  fi
  pass "$label (absent)"
  return 0
}

# --- main ---
resolve_boot "${1:-}"
TREE="$BOOT/pi-ambient-synth"
SECRETS_LOCAL="$ROOT/deploy/secrets/network-config.local"
REF_USER_DATA="$ROOT/deploy/user-data"

echo "=============================================="
echo " Pi Ambient Synth — SD pre-boot validation"
echo " Boot volume: $BOOT"
echo " Expected user: $EXPECTED_USER"
echo "=============================================="

# ---------------------------------------------------------------------------
section "0. Boot sentinel (prove Linux before cloud-init / firstboot)"
# ---------------------------------------------------------------------------
file_must_exist "$TREE/scripts/pi_boot_sentinel.sh" \
  "Boot sentinel script must be on SD (sync repo)"
file_must_exist "$TREE/systemd/pi-ambient-boot-sentinel.service" \
  "Boot sentinel unit must be on SD tree"

if [[ -x "$TREE/scripts/pi_boot_sentinel.sh" ]]; then
  pass "pi_boot_sentinel.sh executable on boot tree"
else
  fail "pi_boot_sentinel.sh not executable — re-run build_factory_sd_mac.sh"
fi

if grep -q 'WantedBy=basic.target' "$TREE/systemd/pi-ambient-boot-sentinel.service" 2>/dev/null; then
  pass "pi-ambient-boot-sentinel.service WantedBy=basic.target"
else
  fail "Boot sentinel unit must run at basic.target (before cloud-init)"
fi

if grep -qE '/boot/firmware|/boot' "$TREE/scripts/pi_boot_sentinel.sh" 2>/dev/null; then
  pass "pi_boot_sentinel writes to /boot/firmware and /boot"
else
  fail "pi_boot_sentinel.sh must write pi-boot-sentinel.txt to both boot paths"
fi

export PATH="/opt/homebrew/Cellar/e2tools/0.1.2/bin:/opt/homebrew/bin:${PATH:-}"
_SENTINEL_ON_ROOT=no
_SENTINEL_CMDLINE=no
if [[ -f "$BOOT/cmdline.txt" ]] && grep -q 'pi_boot_sentinel\.sh' "$BOOT/cmdline.txt" 2>/dev/null; then
  _SENTINEL_CMDLINE=yes
  pass "Boot sentinel in cmdline.txt (systemd.run fallback)"
fi
if command -v e2ls >/dev/null 2>&1; then
  DISK="$(diskutil info "$BOOT" 2>/dev/null | awk '/Device Node/ {print $3; exit}')"
  if [[ "$DISK" =~ ^/dev/disk[0-9]+s[0-9]+$ ]]; then
    DISK_NUM="${DISK#\/dev\/disk}"
    DISK_NUM="${DISK_NUM%s*}"
    ROOT_DEV="/dev/rdisk${DISK_NUM}s2"
    if e2ls "$ROOT_DEV:/etc/systemd/system/pi-ambient-boot-sentinel.service" >/dev/null 2>&1; then
      pass "pi-ambient-boot-sentinel.service installed on SD root FS"
      _SENTINEL_ON_ROOT=yes
      if e2ls "$ROOT_DEV:/etc/systemd/system/basic.target.wants/pi-ambient-boot-sentinel.service" >/dev/null 2>&1; then
        pass "Boot sentinel enabled in basic.target.wants"
      else
        fail "Boot sentinel not enabled on root — run: sudo ./scripts/install_boot_sentinel_rootfs.sh $BOOT"
      fi
    elif [[ "$_SENTINEL_CMDLINE" != yes ]]; then
      fail "Boot sentinel NOT on SD root — run: sudo ./scripts/install_boot_sentinel_rootfs.sh $BOOT (or re-run build_factory_sd_mac.sh for cmdline fallback)"
    fi
  elif [[ "$_SENTINEL_CMDLINE" != yes ]]; then
    echo "WARN: could not resolve SD root partition — verify sentinel install manually"
  fi
else
  [[ "$_SENTINEL_CMDLINE" == yes ]] || echo "WARN: e2tools not installed — cannot verify root FS sentinel (brew install e2tools)"
fi
if [[ "$_SENTINEL_ON_ROOT" != yes && "$_SENTINEL_CMDLINE" != yes ]]; then
  fail "No boot sentinel on root or cmdline — SD will not prove Linux boot"
fi

if [[ -f "$BOOT/pi-boot-sentinel.txt" ]]; then
  pass "pi-boot-sentinel.txt exists (Pi has booted Linux at least once)"
  echo "       $(head -3 "$BOOT/pi-boot-sentinel.txt" | sed 's/^/       /')"
else
  pass "pi-boot-sentinel.txt absent (expected before first Pi boot)"
fi

# ---------------------------------------------------------------------------
section "1. User / SSH"
# ---------------------------------------------------------------------------
if [[ -f "$BOOT/ssh" ]] || [[ -f "$BOOT/firmware/ssh" ]]; then
  pass "SSH enable file (ssh) on boot partition"
else
  fail "No ssh file on boot partition" "./scripts/build_factory_sd_mac.sh $BOOT  (sync touches ssh)"
fi

file_must_exist "$TREE/scripts/lib/pi_install_user.sh" \
  "Sync repo — pi_install_user.sh must be on SD for $EXPECTED_USER paths"

if [[ -x "$TREE/scripts/pi_ambient_firstboot.sh" ]]; then
  pass "pi_ambient_firstboot.sh is executable on SD"
else
  fail "pi_ambient_firstboot.sh missing or not executable on SD"
fi

if grep -q 'pi_install_user' "$TREE/scripts/pi_ambient_firstboot.sh" 2>/dev/null; then
  pass "pi_ambient_firstboot uses pi_install_user (sam/pi auto-detect)"
else
  fail "pi_ambient_firstboot.sh does not source pi_install_user.sh"
fi

if grep -q 'pi_install_dir' "$TREE/scripts/pi_ambient_firstboot.sh" 2>/dev/null \
  && ! grep -qE 'INSTALL_DIR=/home/pi[^-]|/home/pi/pi-ambient' "$TREE/scripts/pi_ambient_firstboot.sh" 2>/dev/null; then
  pass "pi_ambient_firstboot avoids hardcoded /home/pi install path"
else
  fail "pi_ambient_firstboot still hardcodes /home/pi — update and re-sync"
fi

if [[ -f "$BOOT/user-data" ]]; then
  grep_must_not "$BOOT/user-data" '/home/pi' \
    "user-data must not hardcode /home/pi (use pi_ambient_firstboot + pi_install_user)"
  if grep -qE 'install_firstboot_unit|pi-ambient-firstboot\.service' "$BOOT/user-data"; then
    pass "user-data installs pi-ambient-firstboot.service"
  else
    fail "user-data does not install pi-ambient-firstboot unit"
  fi
  if grep -qE 'ssh|sshd' "$BOOT/user-data"; then
    pass "user-data enables SSH"
  else
    fail "user-data does not enable/start ssh"
  fi
else
  fail "Missing $BOOT/user-data"
fi

if [[ -f "$TREE/deploy/deploy.conf" ]]; then
  grep_must_not "$TREE/deploy/deploy.conf" '^INSTALL_DIR=/home/pi' \
    "deploy.conf must not pin INSTALL_DIR=/home/pi only"
  pass "deploy.conf on SD (paths resolved at firstboot)"
else
  fail "Missing $TREE/deploy/deploy.conf"
fi

# Imager user is not stored in our repo; remind operator.
pass "Operator: Pi Imager login must be user '$EXPECTED_USER' (ssh ${EXPECTED_USER}@raspberrypi.local)"

# ---------------------------------------------------------------------------
section "2. WiFi config"
# ---------------------------------------------------------------------------
if [[ -f "$SECRETS_LOCAL" ]]; then
  pass "network-config.local exists in repo ($SECRETS_LOCAL)"
else
  fail "Missing deploy/secrets/network-config.local" \
    "cp deploy/network-config.example deploy/secrets/network-config.local and set SSID/password"
fi

if [[ -f "$BOOT/network-config" ]]; then
  pass "network-config copied to boot partition"
else
  fail "No $BOOT/network-config on SD" \
    "Add deploy/secrets/network-config.local then ./scripts/build_factory_sd_mac.sh $BOOT"
fi

if [[ -f "$BOOT/network-config" ]] && head -1 "$BOOT/network-config" | grep -q '^#cloud-config'; then
  fail "network-config must NOT start with #cloud-config (breaks cloud-init runcmd on Pi)" \
    "Remove header from deploy/secrets/network-config.local and re-run build_factory_sd_mac.sh"
fi

if command -v python3 >/dev/null && [[ -f "$BOOT/network-config" ]]; then
  if python3 - "$BOOT/network-config" "$SECRETS_LOCAL" <<'PY'; then
import sys
try:
    import yaml
except ImportError:
    print("FAIL: PyYAML required on Mac — brew install pyyaml")
    sys.exit(1)

boot_path, local_path = sys.argv[1], sys.argv[2]
for label, path in [("boot", boot_path), ("local", local_path)]:
    with open(path) as f:
        data = yaml.safe_load(f)
    net = (data or {}).get("network", {})
    wifis = net.get("wifis", {})
    wlan = wifis.get("wlan0", {})
    aps = wlan.get("access-points") or wlan.get("access_points") or {}
    if not aps:
        print(f"FAIL: no WiFi access-points in {label} network-config")
        sys.exit(1)
    ssid = next(iter(aps))
    pwd = aps[ssid]
    if isinstance(pwd, dict):
        pwd = pwd.get("password", "")
    if not ssid or not str(ssid).strip():
        print(f"FAIL: empty SSID in {label}")
        sys.exit(1)
    if pwd is None or str(pwd) == "":
        print(f"FAIL: empty password for SSID {ssid!r} in {label}")
        sys.exit(1)
    print(f"OK:   {label} SSID={ssid!r} password length={len(str(pwd))}")

# Re-read raw boot file for unquoted passwords with spaces
raw = open(boot_path).read()
if "password:" in raw:
    import re
    for m in re.finditer(r"password:\s*(.+)$", raw, re.M):
        val = m.group(1).strip()
        if " " in val and not (val.startswith('"') or val.startswith("'")):
            print(f"FAIL: password looks unquoted with spaces: {val[:40]}...")
            sys.exit(1)
print("OK:   network-config YAML parses; SSID + password present; quoting OK")
PY
    :
  else
    fail "network-config YAML validation failed (see above)"
  fi
else
  fail "python3 required to validate network-config" "brew install python3 pyyaml"
fi

# ---------------------------------------------------------------------------
section "3. No legacy blocking boot path"
# ---------------------------------------------------------------------------
if [[ -f "$BOOT/cmdline.txt" ]]; then
  if grep -q 'pi_boot_sentinel\.sh' "$BOOT/cmdline.txt" 2>/dev/null; then
    pass "cmdline systemd.run is boot-sentinel only (allowed)"
    if grep -q 'pi-ambient-synth-firstboot' "$BOOT/cmdline.txt" 2>/dev/null; then
      fail "cmdline must not mix legacy pi-ambient-synth-firstboot with sentinel"
    fi
  else
    grep_must_not "$BOOT/cmdline.txt" 'systemd\.run' \
      "cmdline.txt must not use systemd.run (legacy firstboot blocks cloud-init)"
    grep_must_not "$BOOT/cmdline.txt" 'pi-ambient-synth-firstboot' \
      "cmdline.txt must not reference pi-ambient-synth-firstboot"
    pass "cmdline.txt has no legacy systemd.run firstboot"
  fi
else
  fail "Missing cmdline.txt"
fi

if [[ -f "$BOOT/pi-ambient-synth-firstboot.sh" ]]; then
  fail "Legacy $BOOT/pi-ambient-synth-firstboot.sh present" \
    "Remove it or re-flash without flash_sd_mac cmdline hook; use build_factory_sd_mac.sh only"
else
  pass "No legacy pi-ambient-synth-firstboot.sh on boot partition"
fi

if [[ -f "$BOOT/user-data" ]]; then
  grep_must_not "$BOOT/user-data" '^packages:' \
    "cloud-init must not run apt via packages: (use firstboot-heavy for python3-pil)"
  grep_must_not "$BOOT/user-data" 'install\.sh|pi-deploy-sync|bootstrap' \
    "cloud-init must not run full install/bootstrap inline"
  grep_must_not "$BOOT/user-data" 'apt-get\s+install' \
    "cloud-init runcmd must not apt-get install"
  if diff -q "$REF_USER_DATA" "$BOOT/user-data" >/dev/null 2>&1; then
    pass "user-data matches repo deploy/user-data"
  else
    echo "WARN: user-data differs from repo — ensure you ran build_factory_sd_mac after latest pull"
    if ! grep -q 'install_firstboot_unit' "$BOOT/user-data"; then
      fail "SD user-data is stale (missing install_firstboot_unit)"
    fi
  fi
fi

# ---------------------------------------------------------------------------
section "4. Systemd firstboot + e-ink"
# ---------------------------------------------------------------------------
file_must_exist "$TREE/systemd/pi-ambient-firstboot.service"
file_must_exist "$TREE/scripts/pi_ambient_firstboot.sh"
file_must_exist "$TREE/scripts/install_firstboot_unit.sh"
file_must_exist "$TREE/scripts/firstboot-network-debug.sh"
file_must_exist "$TREE/scripts/eink_official_minimal_test.py"
file_must_exist "$TREE/scripts/eink_known_good_direct_test.sh"
file_must_exist "$TREE/src/eink_official_driver.py"
file_must_exist "$TREE/scripts/eink_display.py"
file_must_exist "$TREE/scripts/eink_early_progress.py"
file_must_exist "$TREE/scripts/lib/eink_exclusive.sh"
file_must_exist "$TREE/vendor/waveshare/waveshare_epd/epd2in13_V4.py"

grep_must_not "$BOOT/user-data" 'bootcmd:|firstboot-light\.sh|eink_boot_early' \
  "user-data must not run bootcmd provisioning or e-ink"
if grep -q 'install_firstboot_unit' "$BOOT/user-data" 2>/dev/null; then
  pass "user-data installs pi-ambient-firstboot.service only"
else
  fail "user-data must call install_firstboot_unit.sh"
fi
if grep -q 'touch /boot/firmware/ssh' "$BOOT/user-data" 2>/dev/null; then
  pass "user-data enables SSH early (independent of firstboot)"
else
  fail "user-data must touch ssh and enable sshd"
fi

if [[ -d "$TREE/boot-logs" ]]; then
  pass "boot-logs/ directory on SD (eink-early.log target)"
else
  fail "Missing $TREE/boot-logs/" "Re-run build_factory_sd_mac.sh"
fi

# Static import guard on early e-ink script
EINK_PY="$TREE/scripts/eink_early_progress.py"
if python3 - "$EINK_PY" <<'PY'; then
import ast, sys
path = sys.argv[1]
tree = ast.parse(open(path).read(), path)
forbidden = ("numpy", "fluidsynth", "mido", "src.", "eink_display", "eink_queue", "main")
bad = []
for node in ast.walk(tree):
    if isinstance(node, ast.Import):
        for n in node.names:
            if any(f in n.name for f in forbidden):
                bad.append(n.name)
    elif isinstance(node, ast.ImportFrom):
        mod = node.module or ""
        if any(f in mod for f in forbidden):
            bad.append(mod)
if bad:
    print("FAIL: forbidden imports:", ", ".join(sorted(set(bad))))
    sys.exit(1)
print("OK:   eink_early_progress.py has no app/numpy/FluidSynth imports")
PY
  :
else
  fail "eink_early_progress.py import check failed"
fi

MINIMAL="$TREE/scripts/eink_official_minimal_test.py"
if grep -q 'vendor/waveshare' "$MINIMAL" && grep -q 'OFFICIAL_SEQUENCE_SENT_TO_PANEL' "$MINIMAL"; then
  pass "eink_official_minimal_test standalone (vendor path, SENT_TO_PANEL)"
else
  fail "eink_official_minimal_test must be self-contained with SENT_TO_PANEL log"
fi
if grep -q 'EINK_VALIDATE_BUSY' "$MINIMAL"; then
  pass "minimal test supports strict BUSY validation mode"
else
  fail "eink_official_minimal_test missing EINK_VALIDATE_BUSY"
fi
file_must_exist "$TREE/scripts/lib/eink_firstboot_log.sh"

if grep -vE '^\s*#' "$TREE/scripts/eink_boot_early.sh" 2>/dev/null | grep -qE \
  'eink_safe_boot_indicator|eink_display\.py|python3.*boot'; then
  fail "eink_boot_early must not call display scripts"
else
  pass "eink_boot_early has no display python calls"
fi

FB="$TREE/scripts/pi_ambient_firstboot.sh"
if grep -q 'POST_START' "$FB" && grep -q 'POST_DONE' "$FB" && grep -q 'FIRSTBOOT_DONE' "$FB"; then
  pass "pi_ambient_firstboot has explicit state machine"
else
  fail "pi_ambient_firstboot.sh missing POST_* / FIRSTBOOT_DONE states"
fi
if grep -q 'firstboot_eink_run_minimal_test' "$FB" && grep -q 'eink_acquire_exclusive' "$FB"; then
  pass "firstboot runs known-good minimal test"
else
  fail "pi_ambient_firstboot must run minimal test with exclusive lock"
fi
if grep -q 'POST_START' "$FB" && grep -q 'RSYNC_START' "$FB"; then
  if awk '/POST_START/{a=NR} /RSYNC_START/{b=NR} END{exit (a>0 && b>a)?0:1}' "$FB"; then
    pass "POST before rsync (boot tree e-ink)"
  else
    fail "pi_ambient_firstboot must POST before RSYNC"
  fi
else
  fail "pi_ambient_firstboot missing POST/RSYNC order"
fi
if grep -q 'firstboot-network-debug' "$FB"; then
  pass "firstboot starts network-debug loop"
else
  fail "pi_ambient_firstboot must start firstboot-network-debug.sh"
fi

if grep -q 'WIFI_WAIT\|WIFI_FAILED' "$EINK_PY"; then
  pass "eink_early_progress has WIFI_WAIT / WIFI_FAILED phases"
else
  fail "eink_early_progress.py missing offline WiFi e-ink phases"
fi

file_must_exist "$TREE/scripts/lib/mask_network_wait.sh"
file_must_exist "$TREE/scripts/lib/wifi_state.sh"
file_must_exist "$TREE/scripts/lib/wifi_debug_bootfs.sh"

if grep -q 'mask_network_wait' "$FB" 2>/dev/null; then
  pass "firstboot masks network wait-online"
else
  fail "pi_ambient_firstboot must mask network wait-online"
fi

if grep -q 'wifi_debug_bootfs\|pi-ambient-wifi-debug' "$FB"; then
  pass "firstboot writes pi-ambient-wifi-debug.txt"
else
  fail "pi_ambient_firstboot must write wifi debug artifact"
fi

if grep -q 'finish_ok\|set +e' "$FB"; then
  pass "firstboot uses set +e and finish_ok"
else
  fail "pi_ambient_firstboot must use set +e and finish_ok"
fi

# ---------------------------------------------------------------------------
section "5. Firstboot stages"
# ---------------------------------------------------------------------------
file_must_exist "$TREE/scripts/firstboot-heavy.sh"
file_must_exist "$TREE/scripts/install-v1-heavy.sh"
file_must_exist "$TREE/systemd/pi-ambient-synth-firstboot-heavy.service"

grep_must_not "$BOOT/user-data" 'firstboot-heavy|firstboot-light\.sh|apt-get' \
  "cloud-init must NOT start heavy or firstboot scripts directly"

if grep -q 'HEAVY_START' "$FB" && grep -q 'firstboot-heavy' "$FB"; then
  pass "pi_ambient_firstboot starts firstboot-heavy via systemd"
else
  fail "pi_ambient_firstboot must trigger firstboot-heavy"
fi

if grep -q 'WantedBy=multi-user.target' "$TREE/systemd/pi-ambient-firstboot.service"; then
  pass "pi-ambient-firstboot.service enabled via multi-user"
else
  fail "pi-ambient-firstboot.service must WantedBy=multi-user.target"
fi

# ---------------------------------------------------------------------------
section "6. Audio mode (fluidsynth V1 only on first boot)"
# ---------------------------------------------------------------------------
if [[ -f "$TREE/deploy/deploy.conf" ]]; then
  grep_must "$TREE/deploy/deploy.conf" '^AUDIO_MODE=fluidsynth' "deploy.conf AUDIO_MODE=fluidsynth"
  if grep -q '^FACTORY_BOOT=1' "$TREE/deploy/deploy.conf" 2>/dev/null; then
    pass "FACTORY_BOOT=1 in deploy.conf"
  else
    echo "WARN: FACTORY_BOOT not set (optional)"
  fi
else
  fail "Missing deploy.conf on SD"
fi

APT_LIST="$TREE/deploy/pi-v1-apt.list"
if [[ -f "$APT_LIST" ]]; then
  pass "pi-v1-apt.list on SD"
  _bad_apt=0
  while IFS= read -r pkg; do
    [[ "$pkg" =~ ^# ]] && continue
    [[ -z "${pkg// }" ]] && continue
    if echo "$pkg" | grep -qiE 'supercollider|jackd2|jackd|xvfb|ghostroll|qt5'; then
      fail "pi-v1-apt.list contains forbidden package: $pkg"
      _bad_apt=1
    fi
  done < "$APT_LIST"
  if [[ $_bad_apt -eq 0 ]]; then
    pass "pi-v1-apt.list excludes SuperCollider/JACK/Xvfb/GhostRoll"
  fi
else
  fail "Missing deploy/pi-v1-apt.list on SD"
fi

# First-boot user-data must not enable SC/JACK
grep_must_not "$BOOT/user-data" 'supercollider|jackd2|pi-deploy-sync.*bootstrap' \
  "user-data must not enable SC/JACK or bootstrap install"

# ---------------------------------------------------------------------------
section "7. Status files"
# ---------------------------------------------------------------------------
if [[ -f "$BOOT/pi-ambient-firstboot-status.txt" ]]; then
  pass "pi-ambient-firstboot-status.txt present (Mac seed; Pi will append)"
  if grep -q 'Mac sync\|not booted yet' "$BOOT/pi-ambient-firstboot-status.txt" 2>/dev/null; then
    pass "Status file has Mac sync marker (Pi not booted yet — expected)"
  fi
else
  fail "Missing pi-ambient-firstboot-status.txt" "./scripts/build_factory_sd_mac.sh $BOOT"
fi

if [[ -f "$BOOT/user-data" ]] && grep -qE 'install_firstboot_unit|pi-ambient-firstboot-status' "$BOOT/user-data"; then
  pass "user-data or install script writes pi-ambient-firstboot-status.txt"
else
  fail "user-data/install_firstboot_unit must write status on boot"
fi

# ---------------------------------------------------------------------------
section "8. Repo bundle sanity"
# ---------------------------------------------------------------------------
if [[ -f "$TREE/scripts/eink_official_minimal_test.py" ]]; then
  pass "eink_official_minimal_test.py on SD (recovery)"
fi

if [[ -d "$TREE/vendor/wheels" ]] && compgen -G "$TREE/vendor/wheels/"'*.whl' >/dev/null; then
  pass "vendor/wheels bundled for offline pip"
else
  echo "WARN: no vendor/wheels — firstboot-heavy may pip from network (slow)"
fi

grep -q '^dtparam=spi=on' "$BOOT/config.txt" 2>/dev/null && pass "dtparam=spi=on in config.txt" \
  || fail "SPI not enabled in config.txt" "Add dtparam=spi=on or re-run sync"

# ---------------------------------------------------------------------------
echo ""
echo "=============================================="
if [[ "$FAILURES" -gt 0 ]]; then
  echo " RESULT: FAILED ($FAILURES check(s))"
  echo "=============================================="
  echo ""
  echo "Do NOT boot this SD until fixed."
  echo ""
  echo "Recommended sequence:"
  echo "  sudo ./scripts/wipe_cloud_init_mac.sh"
  echo "  ./scripts/build_factory_sd_mac.sh $BOOT"
  echo "  ./scripts/check_sd_boot_mac.sh $BOOT"
  exit 1
fi

echo " RESULT: ALL CHECKS PASSED"
echo "=============================================="
echo ""
echo "Safe to boot. Step 1 only — boot sentinel (see docs/boot-sentinel.md):"
echo "  1. Eject SD, boot Pi 3–5 minutes"
echo "  2. Re-insert SD on Mac: cat $BOOT/pi-boot-sentinel.txt"
echo "  3. If NO sentinel: HDMI + LED; try FLASH_ARCH=armhf ./scripts/flash_sd_mac.sh"
echo "  4. Do NOT debug cloud-init / e-ink until sentinel exists"
echo ""
echo "After boot — report (fill in):"
echo "  sentinel file appeared?  yes/no"
echo "  HDMI output?            yes/no — rainbow / kernel / login / emergency / blank"
echo "  image:                   64-bit or 32-bit"
echo "  green LED:               ___"
echo "  bootfs path in file:     /boot or /boot/firmware"
echo ""
echo "After sentinel only:"
echo "      $BOOT/pi-ambient-firstboot-status.txt"
echo "      ssh ${EXPECTED_USER}@raspberrypi.local"
echo ""
exit 0
