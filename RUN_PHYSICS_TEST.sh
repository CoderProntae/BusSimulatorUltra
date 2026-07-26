#!/usr/bin/env bash
# =============================================================================
# Does the bus actually MOVE?
#
#   bash RUN_PHYSICS_TEST.sh
#
# The bus once shipped stuck at 0 km/h: its suspension could carry only 49% of
# its weight and the collision box sat below the tyres, so the hull rested on
# the road and the wheels had no load. Every static check passed. Only running
# the physics catches that, which is what this does.
#
# Downloads Godot 4.4 next to the repo if it is not already there.
# =============================================================================
set -e

cd "$(dirname "$0")"

GODOT_VERSION="4.4"
GODOT_BIN="./godot"
ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${ZIP}"

if [ ! -x "$GODOT_BIN" ]; then
	echo "== Godot ${GODOT_VERSION} indiriliyor =="
	if command -v wget >/dev/null 2>&1; then
		wget -q -O godot.zip "$URL"
	else
		curl -sSL -o godot.zip "$URL"
	fi
	unzip -o -q godot.zip
	mv "Godot_v${GODOT_VERSION}-stable_linux.x86_64" "$GODOT_BIN"
	chmod +x "$GODOT_BIN"
	rm -f godot.zip
fi

echo
echo "== Fizik testi calistiriliyor =="
"$GODOT_BIN" --headless --path res --script ../tools/physics_smoke.gd 2>&1 | tee physics.log

echo
if grep -q "PHYSICS SMOKE TEST PASSED" physics.log; then
	echo "SONUC: GECTI - otobus gercekten hareket ediyor."
	exit 0
fi

echo "SONUC: KALDI - otobus duzgun surmuyor, yukaridaki PHYSICS FAIL satirlarina bak."
exit 1
