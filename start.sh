#!/usr/bin/env bash

echo "Worker Initiated"

if [ -z "$HF_TOKEN" ]; then
    echo "Error: HF_TOKEN is not set."
    exit 1
fi

# Define model storage directories
STABLE_DIFFUSION_MODEL_DIR="/stable-diffusion-webui/models/Stable-diffusion"
EMBEDDINGS_MODEL_DIR="/stable-diffusion-webui/embeddings"
LORAS_MODEL_DIR="/stable-diffusion-webui/models/Lora"

# Ensure model directories exist
mkdir -p "$STABLE_DIFFUSION_MODEL_DIR"
mkdir -p "$EMBEDDINGS_MODEL_DIR"
mkdir -p "$LORAS_MODEL_DIR"

# Function to download a model if not present
download_model() {
    local model_url=$1
    local model_dir=$2
    local model_path="$model_dir/$(basename $model_url)"
    if [ ! -f "$model_path" ]; then
        echo "Downloading model from $model_url to $model_dir using HF_TOKEN"
        wget --header="Authorization: Bearer $HF_TOKEN" -P "$model_dir" "$model_url"
    else
        echo "Model already exists: $(basename $model_path)"
    fi
}

# List of Stable Diffusion model URLs
stable_diffusion_urls=(
    "https://huggingface.co/antonioglass/models/resolve/main/3dAnimationDiffusion_v10.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/epicphotogasm_y.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/general_v3.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/meinahentai_v4.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/semi-realistic_v6.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/Deliberate_v3-inpainting.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/dreamshaper_631Inpainting.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/epicphotogasm_z-inpainting.safetensors"
    "https://huggingface.co/antonioglass/models/resolve/main/meinahentai_v4-inpainting.safetensors"
)

# List of embeddings model URLs
embeddings_urls=(
    "https://huggingface.co/antonioglass/embeddings/resolve/main/BadDream.pt"
    "https://huggingface.co/antonioglass/embeddings/resolve/main/FastNegativeV2.pt"
    "https://huggingface.co/antonioglass/embeddings/resolve/main/UnrealisticDream.pt"
)

# List of LoRa model URLs
lora_urls=(
    "https://huggingface.co/antonioglass/loras/resolve/main/EkuneCowgirl.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/EkunePOVFellatioV2.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/EkuneSideDoggy.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/IPV1.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/JackOPoseFront.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/LickingOralLoRA.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/POVAssGrab.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/POVDoggy.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/POVMissionary.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/POVPaizuri.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/POVReverseCowgirl.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/PSCowgirl.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/RSCongress.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/SelfBreastGrab.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/SideFellatio.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/TheMating.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/cuddling_handjob_v0.1b.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/hand_in_panties_v0.82.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/jkSmallBreastsLite_V01.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/masturbation_female.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/shirtliftv1.safetensors"
    "https://huggingface.co/antonioglass/loras/resolve/main/yamato_v2.safetensors"
)

# Download Stable Diffusion models
for url in "${stable_diffusion_urls[@]}"; do
    download_model "$url" "$STABLE_DIFFUSION_MODEL_DIR"
done

# Download embeddings models
for url in "${embeddings_urls[@]}"; do
    download_model "$url" "$EMBEDDINGS_MODEL_DIR"
done

# Download LoRa models
for url in "${lora_urls[@]}"; do
    download_model "$url" "$LORAS_MODEL_DIR"
done

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