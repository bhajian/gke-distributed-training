FROM pytorch/pytorch:2.4.0-cuda12.1-cudnn9-devel

WORKDIR /workspace

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  git \
  ninja-build \
  cmake \
  && rm -rf /var/lib/apt/lists/*

# Reduce CUDA extension build memory and target A100 (SM80)
ENV MAX_JOBS=1
ENV TORCH_CUDA_ARCH_LIST=8.0

RUN pip install --no-cache-dir \
  "transformers==4.48.3" \
  "tokenizers>=0.20.0" \
  "datasets>=2.20.0" \
  "peft>=0.12.0" \
  "accelerate>=0.30.1" \
  "sentencepiece>=0.2.0" \
  "ninja"

# Build-time CUDA extensions; avoid build isolation so it uses the installed Torch/CUDA
RUN pip install --no-cache-dir --no-build-isolation \
  "mamba-ssm==2.3.1" \
  "causal-conv1d==1.6.1"

COPY src/ /workspace/

CMD ["python", "train.py"]
