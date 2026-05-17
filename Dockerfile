FROM python:3.11-slim
COPY --from=nvidia/cuda:12.2.2-base-ubuntu22.04 /usr/local/cuda/lib64/libcudart.so.12 /usr/lib/x86_64-linux-gnu/libcudart.so.12
COPY server.py /server.py
COPY load_test.py /load_test.py
ENV LD_LIBRARY_PATH=/usr/lib/x86_64-linux-gnu
ENV MODEL_NAME=gpu-worker
ENV PORT=8000
EXPOSE 8000
CMD ["python", "/server.py"]
