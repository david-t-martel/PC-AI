//! PCAI System Module - Native Telemetry and Interrogation
//!
//! Provides optimized access to hardware, OS, and process information.

use sysinfo::{System, Disks, Networks, Components};
use serde::Serialize;

use crate::string::PcaiStringBuffer;

#[derive(Serialize)]
pub struct SystemSummary {
    os_name: String,
    os_version: String,
    hostname: String,
    cpu_count: usize,
    cpu_brand: String,
    memory_total_gb: f64,
    memory_available_gb: f64,
    disks: Vec<DiskInfo>,
    networks: Vec<NetworkInfo>,
    temperatures: Vec<ComponentTemp>,
}

#[derive(Serialize)]
pub struct DiskInfo {
    pub name: String,
    pub mount_point: String,
    pub total_gb: f64,
    pub available_gb: f64,
    pub is_removable: bool,
}

#[derive(Serialize)]
pub struct NetworkInfo {
    pub interface: String,
    pub received_kb: u64,
    pub transmitted_kb: u64,
}

#[derive(Serialize)]
pub struct ComponentTemp {
    pub label: String,
    pub celsius: f32,
}

/// Retrieves a comprehensive summary of system status.
pub fn get_system_summary() -> SystemSummary {
    let mut sys = System::new_all();
    sys.refresh_all();

    let disks_list = Disks::new_with_refreshed_list();
    let disks = disks_list.iter().map(|d| DiskInfo {
        name: d.name().to_string_lossy().into_owned(),
        mount_point: d.mount_point().to_string_lossy().into_owned(),
        total_gb: d.total_space() as f64 / 1_000_000_000.0,
        available_gb: d.available_space() as f64 / 1_000_000_000.0,
        is_removable: d.is_removable(),
    }).collect();

    let networks_list = Networks::new_with_refreshed_list();
    let networks = networks_list.iter().map(|(name, data)| NetworkInfo {
        interface: name.clone(),
        received_kb: data.received() / 1024,
        transmitted_kb: data.transmitted() / 1024,
    }).collect();

    let components_list = Components::new_with_refreshed_list();
    let temperatures = components_list.iter().map(|c| ComponentTemp {
        label: c.label().to_string(),
        celsius: c.temperature(),
    }).collect();

    SystemSummary {
        os_name: System::name().unwrap_or_default(),
        os_version: System::os_version().unwrap_or_default(),
        hostname: System::host_name().unwrap_or_default(),
        cpu_count: sys.cpus().len(),
        cpu_brand: sys.cpus().first().map(|c| c.brand().to_string()).unwrap_or_default(),
        memory_total_gb: sys.total_memory() as f64 / 1_000_000_000.0,
        memory_available_gb: sys.available_memory() as f64 / 1_000_000_000.0,
        disks,
        networks,
        temperatures,
    }
}

// ============================================================================
// FFI Implementation
// ============================================================================

/// Returns a JSON report of the system status.
#[no_mangle]
pub extern "C" fn pcai_query_system_info() -> PcaiStringBuffer {
    let summary = get_system_summary();
    crate::string::json_to_buffer(&summary)
}

/// Specialized query for hardware metrics (temps, CPU usage).
#[no_mangle]
pub extern "C" fn pcai_query_hardware_metrics() -> PcaiStringBuffer {
    let mut sys = System::new();
    sys.refresh_cpu_all();

    #[derive(Serialize)]
    struct Metrics {
        cpu_usage: Vec<f32>,
        avg_load: f32,
        temps: Vec<ComponentTemp>,
    }

    let cpu_usage = sys.cpus().iter().map(|c| c.cpu_usage()).collect();
    let avg_load = sys.global_cpu_usage();

    let components_list = Components::new_with_refreshed_list();
    let temps = components_list.iter().map(|c| ComponentTemp {
        label: c.label().to_string(),
        celsius: c.temperature(),
    }).collect();

    crate::string::json_to_buffer(&Metrics {
        cpu_usage,
        avg_load,
        temps,
    })
}
