use crate::PcaiStatus;
use std::fs;
use std::path::Path;

pub fn delete_item(path: &str, recursive: bool) -> PcaiStatus {
    let path = Path::new(path);
    if !path.exists() {
        return PcaiStatus::PathNotFound;
    }

    let result = if path.is_dir() {
        if recursive {
            fs::remove_dir_all(path)
        } else {
            fs::remove_dir(path)
        }
    } else {
        fs::remove_file(path)
    };

    match result {
        Ok(_) => PcaiStatus::Success,
        Err(e) => match e.kind() {
            std::io::ErrorKind::PermissionDenied => PcaiStatus::PermissionDenied,
            std::io::ErrorKind::NotFound => PcaiStatus::PathNotFound,
            _ => PcaiStatus::IoError,
        },
    }
}
