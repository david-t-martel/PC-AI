# Build Requirements for pcai-inference

## llama.cpp Backend (llamacpp feature)

The llama.cpp backend requires a C++ compiler toolchain to build `llama-cpp-sys-2` from source.

### Windows Requirements

1. **Visual Studio 2019 or later** with:
   - C++ Build Tools
   - Windows 10/11 SDK
   - CMake component

2. **CMake** (if not installed via Visual Studio):
   ```powershell
   winget install Kitware.CMake
   ```

3. **CUDA Toolkit 12.x** (for GPU acceleration):
   - Download from: https://developer.nvidia.com/cuda-downloads
   - Required environment variables:
     - `CUDA_PATH` (usually set automatically)
     - `CUDA_PATH_V12_x` (version-specific)

### Linux Requirements

1. **C++ Compiler**:
   ```bash
   # Ubuntu/Debian
   sudo apt install build-essential cmake

   # Fedora/RHEL
   sudo dnf install gcc-c++ cmake
   ```

2. **CUDA Toolkit** (optional, for GPU):
   ```bash
   # Ubuntu/Debian
   sudo apt install nvidia-cuda-toolkit
   ```

### Build Commands

```powershell
# Windows: Build with llama.cpp backend
cargo build --features llamacpp --release

# Linux: Build with llama.cpp and CUDA
cargo build --features "llamacpp,cuda" --release

# Server mode (default)
cargo build --release

# Library only (no server)
cargo build --lib --no-default-features --features llamacpp
```

### Environment Variables

For CUDA support, you may need to set:
```powershell
# Windows
$env:CUDA_PATH = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.6"

# Linux
export CUDA_PATH=/usr/local/cuda
```

Alternatively, you can auto-detect and configure CUDA for the current session:
```powershell
.\Tools\Initialize-CudaEnvironment.ps1
```

### Common Build Issues

#### "GNU compiler is not supported for this target"

This occurs when the build system detects MinGW/GCC instead of MSVC on Windows.

**Solution**:
1. Install Visual Studio C++ Build Tools
2. Run from "x64 Native Tools Command Prompt for VS 2022"
3. Ensure MSVC is in PATH before MinGW/WSL paths

#### "CMake not found"

**Solution**:
```powershell
winget install Kitware.CMake
# Restart terminal to pick up PATH changes
```

#### "CUDA not found" (when building with cuda feature)

**Solution**:
1. Install CUDA Toolkit
2. Verify `$env:CUDA_PATH` is set
3. Restart terminal

### Pre-built Binaries (Alternative)

If you cannot build from source, you can:

1. **Use mistralrs backend** (CPU-only, no C++ build required)
2. **Build on Linux/WSL** where toolchain setup is simpler
3. **Use Docker** (see Dockerfile)

### Docker Build

```dockerfile
FROM rust:latest
RUN apt-get update && apt-get install -y build-essential cmake
WORKDIR /app
COPY . .
RUN cargo build --release --features llamacpp
```

### Verification

Test that the backend loads correctly:

```rust
use pcai_inference::backends::BackendType;

let backend = BackendType::LlamaCpp.create()?;
assert_eq!(backend.backend_name(), "llama.cpp");
```

### Performance Notes

- **GPU Acceleration**: Requires CUDA 12.x and NVIDIA GPU
- **CPU Inference**: Works on any x64 system with AVX2
- **Memory**: Model loading requires ~4-16GB RAM depending on model size
- **Disk**: GGUF models range from 2GB (7B Q4) to 80GB (70B F16)

### Troubleshooting

For build issues, check:
1. Visual Studio C++ tools are installed
2. CMake is in PATH
3. No conflicting MinGW/WSL paths
4. CUDA_PATH is set (if using GPU)

For runtime issues:
1. GGUF model file exists and is readable
2. Sufficient RAM/VRAM for model
3. GPU drivers are up to date (for CUDA)
