use sysinfo::System;
use std::sync::Mutex;
use std::sync::OnceLock;

static SYS: OnceLock<Mutex<System>> = OnceLock::new();

fn get_system() -> &'static Mutex<System> {
    SYS.get_or_init(|| Mutex::new(System::new_all()))
}

#[derive(Debug, serde::Serialize)]
pub struct SystemTelemetry {
    pub cpu_usage: f32,
    pub memory_used_mb: u64,
    pub memory_total_mb: u64,
    pub gpu_utilization: Option<f32>,
    pub timestamp: u64,
}

/// Collects high-fidelity system telemetry.
pub fn collect_telemetry() -> SystemTelemetry {
    let mut sys = get_system().lock().unwrap();

    // Efficient refresh
    sys.refresh_all(); // Refresh everything for now

    let cpu_usage = sys.global_cpu_usage();
    let memory_used = sys.used_memory() / 1024 / 1024;
    let memory_total = sys.total_memory() / 1024 / 1024;

    // TODO: Integrated NVML support for GPU metrics
    // For now, return None as a placeholder for the safety balancer
    let gpu_utilization = None;

    SystemTelemetry {
        cpu_usage,
        memory_used_mb: memory_used,
        memory_total_mb: memory_total,
        gpu_utilization,
        timestamp: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
    }
}

/// Enforces a system resource safety cap (e.g. 80% load).
/// Returns true if resources are within safe limits.
pub fn check_resource_safety(gpu_limit: f32) -> bool {
    let telemetry = collect_telemetry();

    // If GPU data is available, check it
    if let Some(gpu) = telemetry.gpu_utilization {
        if gpu > (gpu_limit * 100.0) {
            return false;
        }
    }

    // Also check CPU as a secondary safety measure
    if telemetry.cpu_usage > 90.0 {
        return false;
    }

    true
}
