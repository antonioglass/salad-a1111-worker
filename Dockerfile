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

# Download Stable Diffusion models
RUN mkdir -p /stable-diffusion-webui/models/Stable-diffusion && \
    cd /stable-diffusion-webui/models/Stable-diffusion && \
    wget https://huggingface.co/antonioglass/models/resolve/main/3dAnimationDiffusion_v10.safetensors

# Create log directory
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
