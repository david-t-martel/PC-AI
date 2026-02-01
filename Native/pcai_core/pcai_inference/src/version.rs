//! Build version and metadata information.
//!
//! This module provides compile-time embedded version information
//! including git hash, build timestamp, and feature flags.

// Include the auto-generated build info
include!(concat!(env!("OUT_DIR"), "/build_info.rs"));

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version_not_empty() {
        assert!(!VERSION.is_empty());
        assert!(!GIT_HASH.is_empty());
        assert!(!BUILD_TIMESTAMP.is_empty());
    }

    #[test]
    fn test_build_info_format() {
        let info = build_info();
        assert!(info.contains("pcai-inference"));
        assert!(info.contains("Commit:"));
    }

    #[test]
    fn test_build_info_json() {
        let json = build_info_json();
        assert!(json.starts_with('{'));
        assert!(json.ends_with('}'));
        assert!(json.contains("\"version\""));
    }
}
