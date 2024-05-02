#!/usr/bin/env bash

echo "Starting WebUI API"
source /venv/bin/activate
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"
export PYTHONUNBUFFERED=true
export HF_HOME="/"
python /stable-diffusion-webui/webui.py \
  --xformers \
  --skip-python-version-check \
  --skip-torch-cuda-test \
  --skip-install \
  --lowram \
  --opt-sdp-attention \
  --disable-safe-unpickle \
  --port 3000 \
  --api \
  --nowebui \
  --skip-version-check \
  --no-hashing \
  --no-download-sd-model > /logs/webui.log 2>&1 &
deactivate

echo "Starting The Handler"
python3 -u /middleware/app.py