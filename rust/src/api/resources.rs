use std::path::Path;

use sysinfo::{Disks, System};

#[derive(Debug, Clone)]
pub struct HostResources {
    pub total_memory_bytes: u64,
    pub available_memory_bytes: u64,
    pub model_disk_available_bytes: u64,
    pub logical_processors: u32,
}

pub fn probe_host_resources(model_directory: String) -> Result<HostResources, String> {
    let mut system = System::new()
        .map_err(|error| format!("Could not inspect system memory: {error}"))?;
    system.refresh_memory();

    let model_path = Path::new(&model_directory);
    let disks = Disks::new_with_refreshed_list()
        .map_err(|error| format!("Could not inspect model storage: {error}"))?;
    let model_disk_available_bytes = disks
        .iter()
        .filter(|disk| model_path.starts_with(disk.mount_point()))
        .max_by_key(|disk| disk.mount_point().components().count())
        .map(|disk| disk.available_space())
        .ok_or_else(|| "Could not find the model storage volume.".to_owned())?;
    let logical_processors = std::thread::available_parallelism()
        .map_err(|error| format!("Could not inspect processor count: {error}"))?;

    Ok(HostResources {
        total_memory_bytes: system.total_memory(),
        available_memory_bytes: system.available_memory(),
        model_disk_available_bytes,
        logical_processors: logical_processors.get() as u32,
    })
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
