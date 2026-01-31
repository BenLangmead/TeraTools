#!/bin/bash
set -e

echo "Setting up Codex environment for TeraTools..."

# Install build dependencies
echo "Installing build dependencies..."
apt-get update && apt-get install -y \
    build-essential \
    g++ \
    make \
    git \
    libz-dev \
    libatomic1 \
    cmake \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Create and activate virtual environment
echo "Creating Python virtual environment..."
export VIRTUAL_ENV=/opt/venv
python3 -m venv $VIRTUAL_ENV
export PATH="$VIRTUAL_ENV/bin:$PATH"

# Install pydivsufsort
echo "Installing pydivsufsort..."
pip install --no-cache-dir pydivsufsort

# Clone, build and install ropebwt3
echo "Building and installing ropebwt3..."
git clone https://github.com/lh3/ropebwt3 /tmp/ropebwt3
cd /tmp/ropebwt3
make
cp ropebwt3 /usr/local/bin/
cd /
rm -rf /tmp/ropebwt3

# Build TeraTools
echo "Building TeraTools..."
cd /app
make

# Add binaries to PATH
export PATH="/app/src/TeraLCP:/app/src/TeraMS:/app/src/TeraMEM:/app/src/TeraIndex:$PATH"

echo ""
echo "Setup complete! Available binaries:"
echo "  TeraLCP   - RLBWT support structure construction"
echo "  TeraMS    - Matching statistics computation"
echo "  TeraMEM   - Maximal Exact Match enumeration"
echo "  TeraIndex - Index construction and querying"
echo "  ropebwt3  - FM-index construction and searching"
echo ""
echo "Note: To persist the Python virtual environment and PATH changes,"
echo "add the following to your shell profile:"
echo "  export VIRTUAL_ENV=/opt/venv"
echo "  export PATH=\"\$VIRTUAL_ENV/bin:\$PATH\""
echo "  export PATH=\"/app/src/TeraLCP:/app/src/TeraMS:/app/src/TeraMEM:/app/src/TeraIndex:\$PATH\""
