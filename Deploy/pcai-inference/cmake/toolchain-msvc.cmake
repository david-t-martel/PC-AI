# MSVC Toolchain for llama.cpp on Windows
# Ensures proper compiler selection for llama-cpp-sys-2

cmake_minimum_required(VERSION 3.20)

# Force MSVC compiler
set(CMAKE_C_COMPILER "cl.exe")
set(CMAKE_CXX_COMPILER "cl.exe")

# Windows SDK
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)

# MSVC-specific flags
set(CMAKE_C_FLAGS_INIT "/W3 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS")
set(CMAKE_CXX_FLAGS_INIT "/W3 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS /EHsc")

# Release optimization
set(CMAKE_C_FLAGS_RELEASE_INIT "/O2 /Ob2 /DNDEBUG")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "/O2 /Ob2 /DNDEBUG")

# CUDA support (optional)
if(DEFINED ENV{CUDA_PATH})
    set(CMAKE_CUDA_COMPILER "$ENV{CUDA_PATH}/bin/nvcc.exe")
    set(CMAKE_CUDA_HOST_COMPILER "cl.exe")
    message(STATUS "CUDA detected at: $ENV{CUDA_PATH}")
endif()

# Linker flags
set(CMAKE_EXE_LINKER_FLAGS_INIT "/MACHINE:X64")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "/MACHINE:X64")

message(STATUS "Using MSVC toolchain for Windows x64")
