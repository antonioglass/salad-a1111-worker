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
      bc \
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
RUN git clone --depth=1 https://github.com/AUTOMATIC1111/stable-diffusion-webui.git

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

# Cloning the ReActor extension repo
RUN git clone --depth=1 https://github.com/Gourieff/sd-webui-reactor.git extensions/sd-webui-reactor && \
    cd extensions/sd-webui-reactor

# Cloning a person mask generator extension repo
WORKDIR /stable-diffusion-webui
RUN git clone --depth=1 https://github.com/djbielejeski/a-person-mask-generator.git extensions/a-person-mask-generator

# Installing dependencies for ReActor
WORKDIR /stable-diffusion-webui/extensions/sd-webui-reactor
RUN source /venv/bin/activate && \
    pip3 install protobuf==3.20.3 mediapipe==0.10.11 && \
    pip3 install -r requirements.txt && \
    pip3 install onnxruntime-gpu==1.16.3 && \
    deactivate

# Installing dependencies for a person mask generator
WORKDIR /stable-diffusion-webui/extensions/a-person-mask-generator
RUN source /venv/bin/activate && \
    pip3 install -r requirements.txt && \
    deactivate

# Configuring ReActor to use the GPU instead of CPU
RUN echo "CUDA" > last_device.txt

# Installing the models for ReActor
WORKDIR /stable-diffusion-webui/models/insightface
RUN wget https://huggingface.co/antonioglass/reactor/resolve/main/inswapper_128.onnx

WORKDIR /stable-diffusion-webui/models/insightface/models/buffalo_l
RUN wget https://huggingface.co/antonioglass/reactor/resolve/main/buffalo_l/1k3d68.onnx && \
    wget https://huggingface.co/antonioglass/reactor/resolve/main/buffalo_l/2d106det.onnx && \
    wget https://huggingface.co/antonioglass/reactor/resolve/main/buffalo_l/det_10g.onnx && \
    wget https://huggingface.co/antonioglass/reactor/resolve/main/buffalo_l/genderage.onnx && \
    wget https://huggingface.co/antonioglass/reactor/resolve/main/buffalo_l/w600k_r50.onnx

# Installing Codeformer
WORKDIR /stable-diffusion-webui/models/Codeformer
RUN wget https://huggingface.co/antonioglass/reactor/resolve/main/codeformer-v0.1.0.pth

# Installing GFPGAN
WORKDIR /stable-diffusion-webui/models/GFPGAN
RUN wget https://huggingface.co/antonioglass/reactor/resolve/main/detection_Resnet50_Final.pth && \
    wget https://huggingface.co/antonioglass/reactor/resolve/main/parsing_parsenet.pth

# Download a person mask generator model
WORKDIR /stable-diffusion-webui/models/mediapipe
RUN wget https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite

# Download Stable Diffusion models
WORKDIR /stable-diffusion-webui/models/Stable-diffusion
RUN wget https://huggingface.co/antonioglass/models/resolve/main/cyberrealisticPony_v62.safetensors && \
    wget https://huggingface.co/antonioglass/models/resolve/main/cyberrealisticPorn_v62_inpainting_vae.inpainting.safetensors

# Download VAEApprox model
WORKDIR /stable-diffusion-webui/models/VAE-approx
RUN wget https://huggingface.co/antonioglass/models/resolve/main/vaeapprox-sdxl.pt

# Create log directory
WORKDIR /
RUN mkdir -p /logs

# Install config files
RUN cd /stable-diffusion-webui && \
    rm -f webui-user.sh config.json ui-config.json

WORKDIR /
COPY webui-user.sh config.json ui-config.json ./stable-diffusion-webui/

# Prepare the middleware
WORKDIR /
COPY middleware /middleware
RUN pip3 install -r /middleware/requirements.txt

# Add Salad Job Queue Worker
ADD https://github.com/SaladTechnologies/salad-cloud-job-queue-worker/releases/download/v0.3.0/salad-http-job-queue-worker_x86_64.tar.gz /tmp
RUN tar -C /usr/local/bin -zxpf /tmp/salad-http-job-queue-worker_x86_64.tar.gz && \
    rm -rf /tmp/salad-http-job-queue-worker_x86_64.tar.gz

# Set permissions for scripts
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Start the container
CMD /start.sh
