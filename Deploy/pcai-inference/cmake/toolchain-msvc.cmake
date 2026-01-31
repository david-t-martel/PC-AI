# MSVC Toolchain for llama.cpp on Windows
# Ensures proper compiler selection for llama-cpp-sys-2
#
# IMPORTANT: This toolchain requires CC/CXX environment variables to be set
# to the absolute path of cl.exe. The build.ps1 script handles this automatically.

cmake_minimum_required(VERSION 3.20)

# Windows SDK
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)

# Detect MSVC installation path
# Priority: Environment CC/CXX > vswhere detection > PATH lookup
if(DEFINED ENV{CC} AND EXISTS "$ENV{CC}")
    set(CMAKE_C_COMPILER "$ENV{CC}" CACHE FILEPATH "C compiler" FORCE)
    message(STATUS "Using CC from environment: $ENV{CC}")
elseif(DEFINED ENV{CMAKE_C_COMPILER} AND EXISTS "$ENV{CMAKE_C_COMPILER}")
    set(CMAKE_C_COMPILER "$ENV{CMAKE_C_COMPILER}" CACHE FILEPATH "C compiler" FORCE)
    message(STATUS "Using CMAKE_C_COMPILER from environment: $ENV{CMAKE_C_COMPILER}")
else()
    # Fallback: find cl.exe via vswhere
    find_program(VSWHERE_PATH vswhere
        PATHS "$ENV{ProgramFiles\(x86\)}/Microsoft Visual Studio/Installer"
        NO_DEFAULT_PATH
    )
    if(VSWHERE_PATH)
        execute_process(
            COMMAND "${VSWHERE_PATH}" -latest -property installationPath
            OUTPUT_VARIABLE VS_INSTALL_PATH
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(VS_INSTALL_PATH)
            # Find MSVC toolset version
            file(GLOB MSVC_VERSIONS LIST_DIRECTORIES true "${VS_INSTALL_PATH}/VC/Tools/MSVC/*")
            if(MSVC_VERSIONS)
                list(SORT MSVC_VERSIONS)
                list(GET MSVC_VERSIONS -1 MSVC_LATEST)
                set(MSVC_CL "${MSVC_LATEST}/bin/Hostx64/x64/cl.exe")
                if(EXISTS "${MSVC_CL}")
                    set(CMAKE_C_COMPILER "${MSVC_CL}" CACHE FILEPATH "C compiler" FORCE)
                    set(CMAKE_CXX_COMPILER "${MSVC_CL}" CACHE FILEPATH "C++ compiler" FORCE)
                    message(STATUS "Auto-detected MSVC: ${MSVC_CL}")
                endif()
            endif()
        endif()
    endif()
endif()

if(DEFINED ENV{CXX} AND EXISTS "$ENV{CXX}")
    set(CMAKE_CXX_COMPILER "$ENV{CXX}" CACHE FILEPATH "C++ compiler" FORCE)
elseif(DEFINED ENV{CMAKE_CXX_COMPILER} AND EXISTS "$ENV{CMAKE_CXX_COMPILER}")
    set(CMAKE_CXX_COMPILER "$ENV{CMAKE_CXX_COMPILER}" CACHE FILEPATH "C++ compiler" FORCE)
endif()

# MSVC-specific flags
set(CMAKE_C_FLAGS_INIT "/W3 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS")
set(CMAKE_CXX_FLAGS_INIT "/W3 /DWIN32 /D_WINDOWS /D_CRT_SECURE_NO_WARNINGS /EHsc")

# Release optimization
set(CMAKE_C_FLAGS_RELEASE_INIT "/O2 /Ob2 /DNDEBUG")
set(CMAKE_CXX_FLAGS_RELEASE_INIT "/O2 /Ob2 /DNDEBUG")

# Debug flags
set(CMAKE_C_FLAGS_DEBUG_INIT "/Od /Zi /RTC1")
set(CMAKE_CXX_FLAGS_DEBUG_INIT "/Od /Zi /RTC1")

# CUDA support (optional)
if(DEFINED ENV{CUDA_PATH})
    set(CMAKE_CUDA_COMPILER "$ENV{CUDA_PATH}/bin/nvcc.exe")
    set(CMAKE_CUDA_HOST_COMPILER "${CMAKE_CXX_COMPILER}")
    message(STATUS "CUDA detected at: $ENV{CUDA_PATH}")
endif()

# Linker flags
set(CMAKE_EXE_LINKER_FLAGS_INIT "/MACHINE:X64")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "/MACHINE:X64")

message(STATUS "Using MSVC toolchain for Windows x64")
message(STATUS "  C Compiler: ${CMAKE_C_COMPILER}")
message(STATUS "  CXX Compiler: ${CMAKE_CXX_COMPILER}")
