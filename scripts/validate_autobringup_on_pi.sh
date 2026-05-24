#!/usr/bin/env bash
# Acceptance checks for phase-1 autobringup (run on Pi or via ssh).
set -uo pipefail

FAILURES=0
fail() { echo "FAIL: $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "OK:   $*"; }
warn() { echo "WARN: $*"; }

UNIT="pi-ambient-autobringup.service"
MARKER="/var/lib/pi-ambient-synth/autobringup-done"

_log_path() {
  local name="$1"
  for b in /boot/firmware /boot; do
    local f="$b/pi-ambient-synth/boot-logs/${name}.log"
    [[ -f "$f" ]] && { echo "$f"; return 0; }
  done
  return 1
}

echo "=============================================="
echo " Autobringup validation (Pi)"
echo "=============================================="

if systemctl is-enabled "$UNIT" >/dev/null 2>&1; then
  pass "systemd unit enabled"
else
  fail "systemd unit not enabled — run: sudo ./scripts/install_autobringup_on_pi.sh"
fi

st="$(systemctl is-active "$UNIT" 2>/dev/null || echo unknown)"
case "$st" in
  active) pass "systemd unit active (running)" ;;
  inactive)
    if [[ -f "$MARKER" ]]; then
      pass "systemd unit inactive and autobringup-done present (completed)"
    else
      warn "unit inactive, no done marker — may have failed or not started"
    fi
    ;;
  failed) fail "systemd unit failed — journalctl -u $UNIT -b" ;;
  *) warn "systemd is-active: $st" ;;
esac

ab_log="$(_log_path autobringup || true)"
if [[ -n "$ab_log" ]]; then
  pass "autobringup.log exists ($ab_log)"
  if grep -q 'AUTOBRINGUP_START' "$ab_log" 2>/dev/null; then
    pass "AUTOBRINGUP_START in autobringup.log"
  else
    fail "AUTOBRINGUP_START missing — service may not have launched"
  fi
else
  fail "autobringup.log missing on boot partition"
fi

report=""
for b in /boot/firmware /boot; do
  [[ -f "$b/DRIFTLINE_BRINGUP_REPORT.txt" ]] && report="$b/DRIFTLINE_BRINGUP_REPORT.txt" && break
  [[ -f "$b/pi-ambient-synth/DRIFTLINE_BRINGUP_REPORT.txt" ]] && report="$b/pi-ambient-synth/DRIFTLINE_BRINGUP_REPORT.txt" && break
done
if [[ -n "$report" ]] && ! grep -q 'not generated yet' "$report" 2>/dev/null; then
  pass "DRIFTLINE_BRINGUP_REPORT.txt (real report)"
else
  fail "DRIFTLINE_BRINGUP_REPORT.txt missing or still Mac placeholder"
fi

eink_log="$(_log_path eink || true)"
if [[ -n "$eink_log" ]] && grep -q 'EINK_SENT_V4' "$eink_log" 2>/dev/null; then
  pass "EINK_SENT_V4 in eink.log"
else
  fail "EINK_SENT_V4 missing in eink.log"
fi

audio_log="$(_log_path audio || true)"
if [[ -n "$audio_log" ]]; then
  pass "audio.log exists"
  if grep -qE 'AUDIO_INSTALL|fluidsynth|FluidSynth' "$audio_log" 2>/dev/null; then
    pass "audio stages logged"
  else
    warn "audio.log has no obvious install/FluidSynth lines"
  fi
  if grep -q 'KEYSTEP_FOUND' "$audio_log" 2>/dev/null; then
    pass "KeyStep detected"
  else
    warn "KeyStep not found (plug in data USB cable and re-run bring-up with --reset)"
  fi
else
  fail "audio.log missing"
fi

if [[ -f "$MARKER" ]]; then
  pass "autobringup-done marker ($(cat "$MARKER" 2>/dev/null | head -1))"
else
  warn "autobringup-done not set — pipeline may still be running"
fi

echo ""
if [[ -n "$report" ]]; then
  echo "--- report excerpt (summary) ---"
  sed -n '/━━━ SUMMARY/,/━━━ NEXT/p' "$report" 2>/dev/null | head -20 || head -15 "$report"
fi

echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "RESULT: FAILED ($FAILURES) — see journalctl -u $UNIT -b"
  exit 1
fi
echo "RESULT: phase-1 acceptance PASSED"
exit 0
