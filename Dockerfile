FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_PREFER_BINARY=1 \
    PYTHONUNBUFFERED=1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

WORKDIR /

# Upgrade apt packages and install required dependencies
RUN apt update && \
    apt upgrade -y && \
    apt install -y \
      python3-dev \
      python3-pip \
      python3.10-venv \
      fonts-dejavu-core \
      rsync \
      git \
      jq \
      moreutils \
      aria2 \
      wget \
      curl \
      libglib2.0-0 \
      libsm6 \
      libgl1 \
      libxrender1 \
      libxext6 \
      ffmpeg \
      libgoogle-perftools4 \
      libtcmalloc-minimal4 \
      procps && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean -y

# Set Python alias
RUN ln -s /usr/bin/python3.10 /usr/bin/python

# Remove previous installations if any
RUN rm -rf /stable-diffusion-webui /venv

# Clone the A1111 repo
RUN git clone --depth=1 https://github.com/antonioglass/stable-diffusion-webui.git

# Install Python packages
WORKDIR /stable-diffusion-webui
RUN python -m venv --system-site-packages /venv && \
    source /venv/bin/activate && \
    pip3 install --no-cache-dir torch==2.0.1+cu118 torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118 && \
    pip3 install --no-cache-dir xformers==0.0.22 && \
    deactivate

# Install A1111 Web UI
COPY install-automatic.py ./
RUN source /venv/bin/activate && \
    pip3 install -r requirements_versions.txt && \
    python -m install-automatic --skip-torch-cuda-test && \
    deactivate

# Cloning ControlNet extension repo
RUN git clone --depth=1 https://github.com/Mikubill/sd-webui-controlnet.git extensions/sd-webui-controlnet

# Cloning a person mask generator extension repo
RUN git clone --depth=1 https://github.com/djbielejeski/a-person-mask-generator.git extensions/a-person-mask-generator

# Installing dependencies for ControlNet
WORKDIR /stable-diffusion-webui/extensions/sd-webui-controlnet
RUN source /venv/bin/activate && \
    pip3 install -r requirements.txt && \
    deactivate

# Installing dependencies for a person mask generator
WORKDIR /stable-diffusion-webui/extensions/a-person-mask-generator
RUN source /venv/bin/activate && \
    pip3 install -r requirements.txt && \
    deactivate

# Download ControlNet models
WORKDIR /stable-diffusion-webui/models/ControlNet
RUN wget https://huggingface.co/antonioglass/controlnet/resolve/main/controlnet11Models_openpose.safetensors && \
    wget https://huggingface.co/antonioglass/controlnet/raw/main/controlnet11Models_openpose.yaml

# Download a person mask generator model
WORKDIR /stable-diffusion-webui/models/ControlNet
RUN wget https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite

# Download Upscalers
WORKDIR /stable-diffusion-webui/models/ESRGAN
RUN wget https://huggingface.co/antonioglass/upscalers/resolve/main/4x-AnimeSharp.pth && \
    wget https://huggingface.co/antonioglass/upscalers/resolve/main/4x_NMKD-Siax_200k.pth && \
    wget https://huggingface.co/antonioglass/upscalers/resolve/main/8x_NMKD-Superscale_150000_G.pth

# Download Stable Diffusion models
WORKDIR /stable-diffusion-webui/models/Stable-diffusion
RUN wget https://huggingface.co/antonioglass/models/resolve/main/3dAnimationDiffusion_v10.safetensors && \
    wget https://huggingface.co/antonioglass/models/resolve/main/epicphotogasm_y.safetensors && \
    wget https://huggingface.co/antonioglass/models/resolve/main/general_v3.safetensors && \
    wget https://huggingface.co/antonioglass/models/resolve/main/meinahentai_v4.safetensors && \
    wget https://huggingface.co/antonioglass/models/resolve/main/semi-realistic_v6.safetensors

# Create log directory
WORKDIR /
RUN mkdir -p /logs

# Install config files
RUN cd /stable-diffusion-webui && \
    rm -f webui-user.sh config.json ui-config.json && \
    wget https://raw.githubusercontent.com/antonioglass/salad-a1111-worker/main/webui-user.sh && \
    wget https://raw.githubusercontent.com/antonioglass/salad-a1111-worker/main/config.json && \
    wget https://raw.githubusercontent.com/antonioglass/salad-a1111-worker/main/ui-config.json


# Prepare the middleware
WORKDIR /
COPY middleware /middleware
RUN pip install -r /middleware/requirements.txt

# Set permissions for scripts
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Start the container
CMD /start.sh