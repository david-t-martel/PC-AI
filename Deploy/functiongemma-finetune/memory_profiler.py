"""
Memory profiling module for FunctionGemma training.

Tracks GPU and CPU memory usage, estimates training memory requirements,
and warns about potential memory issues.
"""

import warnings
from typing import Dict, Any, Optional

try:
    import psutil
except ImportError:
    raise ImportError(
        "psutil is required for memory profiling. Install with: pip install psutil"
    )

try:
    import torch
except ImportError:
    raise ImportError(
        "torch is required for memory profiling. Install with: pip install torch"
    )


def get_memory_snapshot() -> Dict[str, Any]:
    """
    Get current memory state across CPU, swap, and GPU.

    Returns:
        Dict containing memory information:
        - cpu: dict with total_gb, available_gb, used_gb, percent
        - swap: dict with total_gb, used_gb, percent
        - gpu: dict with available (bool), device_count, devices (list)

    Raises:
        RuntimeError: If psutil fails to get memory information

    Example:
        >>> snapshot = get_memory_snapshot()
        >>> print(f"CPU Available: {snapshot['cpu']['available_gb']:.2f} GB")
        >>> if snapshot['gpu']['available']:
        ...     print(f"GPU Count: {snapshot['gpu']['device_count']}")
    """
    # Get CPU memory
    try:
        vm = psutil.virtual_memory()
        cpu_info = {
            "total_gb": vm.total / (1024**3),
            "available_gb": vm.available / (1024**3),
            "used_gb": vm.used / (1024**3),
            "percent": vm.percent,
        }
    except Exception as e:
        raise RuntimeError(f"Failed to get CPU memory information: {e}")

    # Get swap memory
    try:
        swap = psutil.swap_memory()
        swap_info = {
            "total_gb": swap.total / (1024**3),
            "used_gb": swap.used / (1024**3),
            "percent": swap.percent,
        }

        # Warn if swap usage exceeds 50%
        if swap.percent > 50.0:
            warnings.warn(
                f"High swap usage detected: {swap.percent:.1f}% "
                f"({swap_info['used_gb']:.2f} GB / {swap_info['total_gb']:.2f} GB). "
                "This may significantly slow down training. "
                "Consider closing other applications or adding more RAM.",
                ResourceWarning,
                stacklevel=2,
            )
    except Exception as e:
        raise RuntimeError(f"Failed to get swap memory information: {e}")

    # Get GPU memory
    gpu_info: Dict[str, Any] = {"available": False}

    if torch.cuda.is_available():
        try:
            device_count = torch.cuda.device_count()
            devices = []

            for i in range(device_count):
                props = torch.cuda.get_device_properties(i)
                allocated = torch.cuda.memory_allocated(i)
                reserved = torch.cuda.memory_reserved(i)
                total = props.total_memory

                device_info = {
                    "id": i,
                    "name": props.name,
                    "total_gb": total / (1024**3),
                    "allocated_gb": allocated / (1024**3),
                    "reserved_gb": reserved / (1024**3),
                    "free_gb": (total - allocated) / (1024**3),
                }
                devices.append(device_info)

            gpu_info = {
                "available": True,
                "device_count": device_count,
                "devices": devices,
            }
        except Exception as e:
            warnings.warn(
                f"Failed to get detailed GPU memory information: {e}. "
                "GPU detected but memory stats unavailable.",
                RuntimeWarning,
                stacklevel=2,
            )
            gpu_info = {"available": True, "device_count": 0, "devices": []}

    return {"cpu": cpu_info, "swap": swap_info, "gpu": gpu_info}


def estimate_training_memory(
    model_size_params: int,
    batch_size: int,
    dtype: str = "fp32",
    sequence_length: int = 512,
    gradient_accumulation_steps: int = 1,
) -> Dict[str, float]:
    """
    Estimate memory requirements for training a language model.

    This function estimates memory needed for:
    - Model parameters
    - Optimizer states (assumes AdamW with 2x parameters)
    - Gradients
    - Activations (proportional to batch size and sequence length)

    Args:
        model_size_params: Number of model parameters (e.g., 2_000_000_000 for 2B)
        batch_size: Training batch size per device
        dtype: Data type for training ("fp32", "fp16", or "int8")
        sequence_length: Maximum sequence length (default: 512)
        gradient_accumulation_steps: Number of gradient accumulation steps (default: 1)

    Returns:
        Dict containing memory estimates in GB:
        - model_memory_gb: Memory for model parameters
        - optimizer_memory_gb: Memory for optimizer states
        - gradient_memory_gb: Memory for gradients
        - activation_memory_gb: Memory for activations
        - total_estimated_gb: Total estimated memory
        - recommended_gpu_memory_gb: Recommended GPU memory (with safety margin)

    Raises:
        ValueError: If parameters are invalid

    Example:
        >>> estimate = estimate_training_memory(
        ...     model_size_params=2_000_000_000,
        ...     batch_size=4,
        ...     dtype="fp16"
        ... )
        >>> print(f"Total estimated: {estimate['total_estimated_gb']:.2f} GB")
        >>> print(f"Recommended GPU: {estimate['recommended_gpu_memory_gb']:.2f} GB")
    """
    # Validate inputs
    if model_size_params <= 0:
        raise ValueError(
            f"model_size_params must be positive, got {model_size_params}"
        )
    if batch_size <= 0:
        raise ValueError(f"batch_size must be positive, got {batch_size}")
    if sequence_length <= 0:
        raise ValueError(f"sequence_length must be positive, got {sequence_length}")

    # Bytes per parameter based on dtype
    dtype_bytes = {
        "fp32": 4,
        "float32": 4,
        "fp16": 2,
        "float16": 2,
        "bfloat16": 2,
        "bf16": 2,
        "int8": 1,
        "int4": 0.5,
    }

    if dtype not in dtype_bytes:
        raise ValueError(
            f"Unsupported dtype: {dtype}. "
            f"Supported types: {', '.join(dtype_bytes.keys())}"
        )

    bytes_per_param = dtype_bytes[dtype]

    # Calculate memory components
    # 1. Model parameters
    model_memory_gb = (model_size_params * bytes_per_param) / (1024**3)

    # 2. Optimizer states (AdamW keeps 2 copies: momentum and variance)
    # Optimizer typically uses FP32 regardless of model dtype
    optimizer_memory_gb = (model_size_params * 4 * 2) / (1024**3)

    # 3. Gradients (same size as model parameters)
    gradient_memory_gb = model_memory_gb

    # 4. Activations (proportional to batch size, sequence length, and hidden size)
    # Rule of thumb: ~12 bytes per token per layer for transformer models
    # Assuming ~32 layers for typical LLMs (scales with model size)
    num_layers = max(12, int((model_size_params / 100_000_000) ** 0.5))
    effective_batch_size = batch_size / gradient_accumulation_steps
    bytes_per_token_per_layer = 12 if dtype == "fp32" else 8

    activation_memory_gb = (
        effective_batch_size
        * sequence_length
        * num_layers
        * bytes_per_token_per_layer
    ) / (1024**3)

    # Total estimated memory
    total_estimated_gb = (
        model_memory_gb
        + optimizer_memory_gb
        + gradient_memory_gb
        + activation_memory_gb
    )

    # Recommended memory includes safety margin (1.3x for overhead)
    safety_margin = 1.3
    recommended_gpu_memory_gb = total_estimated_gb * safety_margin

    return {
        "model_memory_gb": model_memory_gb,
        "optimizer_memory_gb": optimizer_memory_gb,
        "gradient_memory_gb": gradient_memory_gb,
        "activation_memory_gb": activation_memory_gb,
        "total_estimated_gb": total_estimated_gb,
        "recommended_gpu_memory_gb": recommended_gpu_memory_gb,
        "dtype": dtype,
        "bytes_per_param": bytes_per_param,
        "estimated_layers": num_layers,
    }


def check_available_memory(
    required_memory_gb: float, device: str = "gpu"
) -> Dict[str, Any]:
    """
    Check if sufficient memory is available for training.

    Args:
        required_memory_gb: Required memory in GB
        device: Device type ("gpu" or "cpu")

    Returns:
        Dict containing:
        - available: bool indicating if sufficient memory is available
        - available_memory_gb: Available memory in GB
        - required_memory_gb: Required memory in GB
        - deficit_gb: Memory deficit if insufficient (0 if available)
        - warnings: List of warning messages

    Example:
        >>> check = check_available_memory(required_memory_gb=24.0, device="gpu")
        >>> if not check['available']:
        ...     print(f"Insufficient memory: {check['deficit_gb']:.2f} GB short")
    """
    snapshot = get_memory_snapshot()
    warnings_list = []

    if device.lower() == "gpu":
        if not snapshot["gpu"]["available"]:
            return {
                "available": False,
                "available_memory_gb": 0.0,
                "required_memory_gb": required_memory_gb,
                "deficit_gb": required_memory_gb,
                "warnings": ["No GPU available"],
            }

        # Check first GPU (can be extended to check all GPUs)
        gpu_device = snapshot["gpu"]["devices"][0]
        available_memory_gb = gpu_device["free_gb"]

        # Check swap usage
        if snapshot["swap"]["percent"] > 50.0:
            warnings_list.append(
                f"High swap usage: {snapshot['swap']['percent']:.1f}%. "
                "May impact performance."
            )

    else:  # CPU
        available_memory_gb = snapshot["cpu"]["available_gb"]

        # Warn if available memory is low
        if snapshot["cpu"]["percent"] > 80.0:
            warnings_list.append(
                f"High CPU memory usage: {snapshot['cpu']['percent']:.1f}%. "
                "May cause OOM errors."
            )

    available = available_memory_gb >= required_memory_gb
    deficit_gb = max(0.0, required_memory_gb - available_memory_gb)

    if not available:
        warnings_list.append(
            f"Insufficient memory: need {required_memory_gb:.2f} GB, "
            f"but only {available_memory_gb:.2f} GB available. "
            f"Deficit: {deficit_gb:.2f} GB"
        )

    return {
        "available": available,
        "available_memory_gb": available_memory_gb,
        "required_memory_gb": required_memory_gb,
        "deficit_gb": deficit_gb,
        "warnings": warnings_list,
    }


if __name__ == "__main__":
    # Example usage
    print("=" * 60)
    print("Memory Profiler - Current System State")
    print("=" * 60)

    snapshot = get_memory_snapshot()

    print(f"\nCPU Memory:")
    print(f"  Total: {snapshot['cpu']['total_gb']:.2f} GB")
    print(f"  Available: {snapshot['cpu']['available_gb']:.2f} GB")
    print(f"  Used: {snapshot['cpu']['used_gb']:.2f} GB ({snapshot['cpu']['percent']:.1f}%)")

    print(f"\nSwap Memory:")
    print(f"  Total: {snapshot['swap']['total_gb']:.2f} GB")
    print(f"  Used: {snapshot['swap']['used_gb']:.2f} GB ({snapshot['swap']['percent']:.1f}%)")

    if snapshot["gpu"]["available"]:
        print(f"\nGPU Memory:")
        print(f"  Device Count: {snapshot['gpu']['device_count']}")
        for device in snapshot["gpu"]["devices"]:
            print(f"\n  Device {device['id']}: {device['name']}")
            print(f"    Total: {device['total_gb']:.2f} GB")
            print(f"    Allocated: {device['allocated_gb']:.2f} GB")
            print(f"    Reserved: {device['reserved_gb']:.2f} GB")
            print(f"    Free: {device['free_gb']:.2f} GB")
    else:
        print("\nGPU: Not available")

    print("\n" + "=" * 60)
    print("Memory Estimation for 2B Model (FP16, Batch Size 4)")
    print("=" * 60)

    estimate = estimate_training_memory(
        model_size_params=2_000_000_000, batch_size=4, dtype="fp16"
    )

    print(f"\nModel Memory: {estimate['model_memory_gb']:.2f} GB")
    print(f"Optimizer Memory: {estimate['optimizer_memory_gb']:.2f} GB")
    print(f"Gradient Memory: {estimate['gradient_memory_gb']:.2f} GB")
    print(f"Activation Memory: {estimate['activation_memory_gb']:.2f} GB")
    print(f"Total Estimated: {estimate['total_estimated_gb']:.2f} GB")
    print(
        f"Recommended GPU Memory: {estimate['recommended_gpu_memory_gb']:.2f} GB "
        "(with safety margin)"
    )

    # Check if training is feasible
    if snapshot["gpu"]["available"]:
        check = check_available_memory(
            required_memory_gb=estimate["total_estimated_gb"], device="gpu"
        )
        print(f"\nTraining Feasibility: {'YES' if check['available'] else 'NO'}")
        if not check["available"]:
            print(f"  Memory deficit: {check['deficit_gb']:.2f} GB")
        for warning in check["warnings"]:
            print(f"  WARNING: {warning}")
