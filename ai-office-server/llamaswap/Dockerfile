FROM ghcr.io/mostlygeek/llama-swap:vulkan
RUN apt-get update && apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  git \
  && rm -rf /var/lib/apt/lists/*

ENV VIRTUAL_ENV=/opt/vllm
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN pip install vllm