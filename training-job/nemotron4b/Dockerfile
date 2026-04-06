FROM pytorch/pytorch:2.2.2-cuda12.1-cudnn8-runtime

WORKDIR /workspace

RUN pip install --no-cache-dir \
  transformers==4.41.2 \
  datasets==2.19.2 \
  peft==0.11.1 \
  accelerate==0.30.1 \
  sentencepiece==0.2.0

COPY src/ /workspace/

CMD ["python", "train.py"]
