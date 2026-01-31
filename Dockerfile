FROM ghcr.io/openai/codex-universal:latest

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    make \
    git \
    libz-dev \
    libatomic1 \
    cmake \
    python3 \
    python3-pip \
    && rm -rf /var/lib/apt/lists/*

# Install pydivsufsort
RUN pip3 install --no-cache-dir pydivsufsort

# Set working directory
WORKDIR /app

# Copy the entire repository
COPY . .

# Build all binaries
# This will:
# 1. Clone and build ropebwt3 dependency
# 2. Build sdsl-lite library in src/thirdparty/
# 3. Build all TeraTools binaries: TeraLCP, TeraMS, TeraMEM, TeraIndex
RUN make

# Add binaries to PATH
ENV PATH="/app/src/TeraLCP:/app/src/TeraMS:/app/src/TeraMEM:/app/src/TeraIndex:${PATH}"

# Set default command to show available binaries
CMD ["bash", "-c", "echo 'TeraTools binaries available:' && \
    echo '  TeraLCP   - RLBWT support structure construction' && \
    echo '  TeraMS    - Matching statistics computation' && \
    echo '  TeraMEM   - Maximal Exact Match enumeration' && \
    echo '  TeraIndex - Index construction and querying' && \
    echo '' && \
    echo 'Use: docker run <image> <binary> <args>'"]
