FROM pytorch/pytorch:2.2.2-cuda12.1-cudnn8-runtime

WORKDIR /workspace

RUN pip install --no-cache-dir scikit-learn==1.5.0 pandas==2.2.2

COPY src/ /workspace/

CMD ["python", "train.py"]
