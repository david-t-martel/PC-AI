//! Filesystem operations helper functions
//!
//! Internal utilities for file operations, not exposed via FFI.
//! Reserved for future expansion.

use std::path::Path;

/// Check if path is safe to delete (not system directory)
pub fn is_safe_to_delete(path: &Path) -> bool {
    // Basic safety checks
    if !path.exists() {
        return false;
    }

    // Don't delete root directories
    if path.parent().is_none() {
        return false;
    }

    // Don't delete Windows system directories
    #[cfg(windows)]
    {
        if let Some(path_str) = path.to_str() {
            let lower = path_str.to_lowercase();
            if lower.starts_with("c:\\windows")
                || lower.starts_with("c:\\program files")
                || lower.starts_with("c:\\system")
            {
                return false;
            }
        }
    }

    true
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    #[test]
    fn test_safe_delete_nonexistent() {
        let path = PathBuf::from("/nonexistent/path");
        assert!(!is_safe_to_delete(&path));
    }

    #[test]
    #[cfg(windows)]
    fn test_safe_delete_system_dirs() {
        assert!(!is_safe_to_delete(Path::new("C:\\Windows")));
        assert!(!is_safe_to_delete(Path::new("C:\\Program Files")));
    }
}
