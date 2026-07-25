#!/usr/bin/env bash
# =============================================================================
# BusSimulatorUltra - tek komutla gonderme scripti
#
#   bash PUSH.sh
#
# BU SCRIPT BILEREK **PR ACMAZ** VE **MERGE ETMEZ**.
# Arena oturumu PR merge/close edilirse OLUR. Sadece push guvenlidir.
# Push edilince GitHub Actions otomatik calisir ve APK uretir.
# =============================================================================
set -e

BRANCH="arena/019f9afc-bussimulatorultra"

cd "$(dirname "$0")"

CURRENT="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT" != "$BRANCH" ]; then
	echo "HATA: yanlis branch'tesin: $CURRENT"
	echo "Bu oturum sadece $BRANCH uzerinde calisir."
	echo "Cozum:  git checkout $BRANCH"
	exit 1
fi

echo "== Degisiklikler =="
git status --short

if [ -n "$(git status --porcelain)" ]; then
	echo
	echo "Commit edilmemis degisiklikler var, commit ediliyor..."
	git add -A
	git commit -m "chore: local changes"
fi

echo
echo "== Push: origin/$BRANCH =="
git push origin "$BRANCH"

echo
echo "TAMAM. Hicbir PR acilmadi, hicbir sey merge edilmedi."
echo "CI:   https://github.com/CoderProntae/BusSimulatorUltra/actions"
echo "APK:  en ustteki calisma -> Artifacts -> BusSimulator-APK"
