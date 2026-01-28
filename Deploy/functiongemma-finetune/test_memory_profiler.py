"""
Test suite for memory_profiler module.

Tests memory profiling functionality for FunctionGemma training.
"""

import pytest
from unittest.mock import Mock, patch, MagicMock
import warnings


class TestMemorySnapshot:
    """Test get_memory_snapshot() function."""

    @patch("psutil.virtual_memory")
    @patch("psutil.swap_memory")
    @patch("torch.cuda.is_available")
    def test_memory_snapshot_cpu_only(
        self, mock_cuda_available, mock_swap_memory, mock_virtual_memory
    ):
        """Test memory snapshot when no GPU is available."""
        # Mock CPU and swap memory
        mock_virtual_memory.return_value = Mock(
            total=16 * 1024**3,  # 16 GB
            available=8 * 1024**3,  # 8 GB available
            percent=50.0,
            used=8 * 1024**3,
        )
        mock_swap_memory.return_value = Mock(
            total=4 * 1024**3,  # 4 GB swap
            used=1 * 1024**3,  # 1 GB used
            percent=25.0,
        )
        mock_cuda_available.return_value = False

        from memory_profiler import get_memory_snapshot

        snapshot = get_memory_snapshot()

        assert "cpu" in snapshot
        assert "swap" in snapshot
        assert "gpu" in snapshot
        assert snapshot["cpu"]["total_gb"] == 16.0
        assert snapshot["cpu"]["available_gb"] == 8.0
        assert snapshot["cpu"]["used_gb"] == 8.0
        assert snapshot["cpu"]["percent"] == 50.0
        assert snapshot["swap"]["total_gb"] == 4.0
        assert snapshot["swap"]["used_gb"] == 1.0
        assert snapshot["swap"]["percent"] == 25.0
        assert snapshot["gpu"]["available"] is False

    @patch("psutil.virtual_memory")
    @patch("psutil.swap_memory")
    @patch("torch.cuda.is_available")
    @patch("torch.cuda.device_count")
    @patch("torch.cuda.get_device_properties")
    @patch("torch.cuda.memory_allocated")
    @patch("torch.cuda.memory_reserved")
    def test_memory_snapshot_with_gpu(
        self,
        mock_memory_reserved,
        mock_memory_allocated,
        mock_device_properties,
        mock_device_count,
        mock_cuda_available,
        mock_swap_memory,
        mock_virtual_memory,
    ):
        """Test memory snapshot when GPU is available."""
        # Mock CPU and swap memory
        mock_virtual_memory.return_value = Mock(
            total=32 * 1024**3,
            available=16 * 1024**3,
            percent=50.0,
            used=16 * 1024**3,
        )
        mock_swap_memory.return_value = Mock(
            total=8 * 1024**3, used=0, percent=0.0
        )

        # Mock GPU
        mock_cuda_available.return_value = True
        mock_device_count.return_value = 1
        mock_device_properties.return_value = Mock(
            name="NVIDIA RTX 4090", total_memory=24 * 1024**3
        )
        mock_memory_allocated.return_value = 8 * 1024**3  # 8 GB allocated
        mock_memory_reserved.return_value = 10 * 1024**3  # 10 GB reserved

        from memory_profiler import get_memory_snapshot

        snapshot = get_memory_snapshot()

        assert snapshot["gpu"]["available"] is True
        assert snapshot["gpu"]["device_count"] == 1
        assert len(snapshot["gpu"]["devices"]) == 1
        assert snapshot["gpu"]["devices"][0]["name"] == "NVIDIA RTX 4090"
        assert snapshot["gpu"]["devices"][0]["total_gb"] == 24.0
        assert snapshot["gpu"]["devices"][0]["allocated_gb"] == 8.0
        assert snapshot["gpu"]["devices"][0]["reserved_gb"] == 10.0
        assert snapshot["gpu"]["devices"][0]["free_gb"] == 14.0

    @patch("psutil.virtual_memory")
    @patch("psutil.swap_memory")
    @patch("torch.cuda.is_available")
    def test_memory_snapshot_high_swap_warning(
        self, mock_cuda_available, mock_swap_memory, mock_virtual_memory
    ):
        """Test that warning is issued when swap usage exceeds 50%."""
        mock_virtual_memory.return_value = Mock(
            total=16 * 1024**3,
            available=4 * 1024**3,
            percent=75.0,
            used=12 * 1024**3,
        )
        mock_swap_memory.return_value = Mock(
            total=8 * 1024**3,
            used=5 * 1024**3,  # 62.5% swap usage
            percent=62.5,
        )
        mock_cuda_available.return_value = False

        from memory_profiler import get_memory_snapshot

        with warnings.catch_warnings(record=True) as w:
            warnings.simplefilter("always")
            snapshot = get_memory_snapshot()

            # Check warning was issued
            assert len(w) == 1
            assert "swap usage" in str(w[0].message).lower()
            assert "62.5%" in str(w[0].message)

        assert snapshot["swap"]["percent"] == 62.5


class TestEstimateTrainingMemory:
    """Test estimate_training_memory() function."""

    def test_estimate_fp32_memory(self):
        """Test memory estimation for FP32 training."""
        from memory_profiler import estimate_training_memory

        # 1B parameter model, batch size 4, fp32
        estimate = estimate_training_memory(
            model_size_params=1_000_000_000, batch_size=4, dtype="fp32"
        )

        assert "model_memory_gb" in estimate
        assert "optimizer_memory_gb" in estimate
        assert "gradient_memory_gb" in estimate
        assert "activation_memory_gb" in estimate
        assert "total_estimated_gb" in estimate
        assert "recommended_gpu_memory_gb" in estimate

        # FP32: 4 bytes per parameter
        # Model: 1B * 4 = 4GB
        # Optimizer (AdamW): 2 * model = 8GB
        # Gradients: 1 * model = 4GB
        # Activations: proportional to batch size
        assert estimate["model_memory_gb"] == pytest.approx(4.0, rel=0.01)
        assert estimate["optimizer_memory_gb"] == pytest.approx(8.0, rel=0.01)
        assert estimate["gradient_memory_gb"] == pytest.approx(4.0, rel=0.01)
        assert estimate["total_estimated_gb"] > 16.0

    def test_estimate_fp16_memory(self):
        """Test memory estimation for FP16 training."""
        from memory_profiler import estimate_training_memory

        # 2B parameter model, batch size 2, fp16
        estimate = estimate_training_memory(
            model_size_params=2_000_000_000, batch_size=2, dtype="fp16"
        )

        # FP16: 2 bytes per parameter
        # Model: 2B * 2 = 4GB
        assert estimate["model_memory_gb"] == pytest.approx(4.0, rel=0.01)
        assert estimate["total_estimated_gb"] < estimate_training_memory(
            model_size_params=2_000_000_000, batch_size=2, dtype="fp32"
        )["total_estimated_gb"]

    def test_estimate_int8_memory(self):
        """Test memory estimation for INT8 quantized training."""
        from memory_profiler import estimate_training_memory

        # 2B parameter model, batch size 8, int8
        estimate = estimate_training_memory(
            model_size_params=2_000_000_000, batch_size=8, dtype="int8"
        )

        # INT8: 1 byte per parameter
        # Model: 2B * 1 = 2GB
        assert estimate["model_memory_gb"] == pytest.approx(2.0, rel=0.01)
        assert estimate["total_estimated_gb"] < estimate_training_memory(
            model_size_params=2_000_000_000, batch_size=8, dtype="fp16"
        )["total_estimated_gb"]

    def test_estimate_batch_size_scaling(self):
        """Test that memory estimate scales with batch size."""
        from memory_profiler import estimate_training_memory

        estimate_small = estimate_training_memory(
            model_size_params=1_000_000_000, batch_size=1, dtype="fp32"
        )
        estimate_large = estimate_training_memory(
            model_size_params=1_000_000_000, batch_size=8, dtype="fp32"
        )

        # Activation memory should scale with batch size
        assert estimate_large["activation_memory_gb"] > estimate_small[
            "activation_memory_gb"
        ]
        assert estimate_large["total_estimated_gb"] > estimate_small["total_estimated_gb"]

    def test_estimate_invalid_dtype(self):
        """Test that invalid dtype raises ValueError."""
        from memory_profiler import estimate_training_memory

        with pytest.raises(ValueError, match="Unsupported dtype"):
            estimate_training_memory(
                model_size_params=1_000_000_000, batch_size=4, dtype="invalid"
            )

    def test_estimate_zero_batch_size(self):
        """Test that zero batch size raises ValueError."""
        from memory_profiler import estimate_training_memory

        with pytest.raises(ValueError, match="batch_size must be positive"):
            estimate_training_memory(
                model_size_params=1_000_000_000, batch_size=0, dtype="fp32"
            )

    def test_estimate_negative_model_size(self):
        """Test that negative model size raises ValueError."""
        from memory_profiler import estimate_training_memory

        with pytest.raises(ValueError, match="model_size_params must be positive"):
            estimate_training_memory(
                model_size_params=-1000, batch_size=4, dtype="fp32"
            )


class TestMemoryProfilerIntegration:
    """Integration tests for memory profiler."""

    @patch("psutil.virtual_memory")
    @patch("psutil.swap_memory")
    @patch("torch.cuda.is_available")
    def test_snapshot_before_training(
        self, mock_cuda_available, mock_swap_memory, mock_virtual_memory
    ):
        """Test getting memory snapshot before training."""
        mock_virtual_memory.return_value = Mock(
            total=32 * 1024**3,
            available=20 * 1024**3,
            percent=37.5,
            used=12 * 1024**3,
        )
        mock_swap_memory.return_value = Mock(
            total=8 * 1024**3, used=0, percent=0.0
        )
        mock_cuda_available.return_value = False

        from memory_profiler import get_memory_snapshot, estimate_training_memory

        # Get current state
        snapshot = get_memory_snapshot()
        assert snapshot["cpu"]["available_gb"] == 20.0

        # Estimate requirements
        estimate = estimate_training_memory(
            model_size_params=2_000_000_000, batch_size=4, dtype="fp16"
        )

        # Verify we have enough memory
        assert snapshot["cpu"]["available_gb"] >= estimate["total_estimated_gb"] * 0.5

    def test_recommended_memory_includes_safety_margin(self):
        """Test that recommended memory includes safety margin."""
        from memory_profiler import estimate_training_memory

        estimate = estimate_training_memory(
            model_size_params=1_000_000_000, batch_size=4, dtype="fp32"
        )

        # Recommended should be higher than estimated (safety margin)
        assert estimate["recommended_gpu_memory_gb"] > estimate["total_estimated_gb"]
        # Safety margin should be reasonable (typically 1.2-1.5x)
        margin = (
            estimate["recommended_gpu_memory_gb"] / estimate["total_estimated_gb"]
        )
        assert 1.1 <= margin <= 2.0
