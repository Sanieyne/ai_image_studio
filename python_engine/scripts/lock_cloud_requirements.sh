#!/usr/bin/env bash
# Regenerate requirements-cloud.lock from a clean install on the cloud image's torch,
# then check it with the self-test. CPU-only; needs Python 3.12 (as in the image).
#   python_engine/scripts/lock_cloud_requirements.sh [torch_version]
set -euo pipefail
TORCH="${1:-2.11.0}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
python3.12 -m venv "$WORK/v"
P="$WORK/v/bin/pip"
"$P" install -q --upgrade pip
"$P" install -q --index-url https://download.pytorch.org/whl/cpu "torch==$TORCH" "torchaudio==$TORCH" torchvision
"$P" install -q -r "$HERE/requirements.txt"
"$P" install -q --no-deps chatterbox-tts==0.1.7
(cd "$HERE" && AI_STUDIO_MOCK=1 "$WORK/v/bin/python" self_test.py)
{
  echo "# Cloud engine: locked, tested package set (generated $(date -u +%F) from a clean install)."
  echo "# Base image torch $TORCH (cu128). Install: pip install -r requirements-cloud.lock -c constraints-cloud.txt"
  echo "#   then:  pip install --no-deps chatterbox-tts==0.1.7"
  "$P" freeze --exclude-editable | grep -viE '^(torch|torchaudio|torchvision|pip|setuptools|wheel|chatterbox-tts)==' | sed -E 's/\+cpu//'
} > "$HERE/requirements-cloud.lock"
echo "Wrote $HERE/requirements-cloud.lock"
