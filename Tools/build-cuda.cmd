@echo off
setlocal

set CUDA_PATH=C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v13.0
set PATH=%PATH%;%CUDA_PATH%\bin;%CUDA_PATH%\nvvm\bin

echo CUDA_PATH: %CUDA_PATH%
echo Checking nvcc...
where nvcc
echo Checking cicc...
where cicc

echo.
echo Building rust-functiongemma-train with CUDA...
cd /d C:\Users\david\PC_AI
cargo build --manifest-path Deploy\rust-functiongemma-train\Cargo.toml
