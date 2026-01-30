use pcai_fs::*;
use std::ffi::CString;
use std::fs;
use tempfile::TempDir;

#[test]
fn test_pcai_fs_version() {
    let version = pcai_fs_version();
    assert!(version >= 1, "Version should be at least 1");
}

#[test]
fn test_pcai_delete_fs_item_file() {
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.txt");
    fs::write(&file_path, "test content").unwrap();
    assert!(file_path.exists());

    let path_cstr = CString::new(file_path.to_str().unwrap()).unwrap();
    unsafe {
        let status = pcai_delete_fs_item(path_cstr.as_ptr(), false);
        assert_eq!(status, PcaiStatus::Success);
    }
    assert!(!file_path.exists());
}

#[test]
fn test_pcai_delete_fs_item_dir_recursive() {
    let temp_dir = TempDir::new().unwrap();
    let sub_dir = temp_dir.path().join("subdir");
    fs::create_dir(&sub_dir).unwrap();
    fs::write(sub_dir.join("file.txt"), "content").unwrap();

    let path_cstr = CString::new(sub_dir.to_str().unwrap()).unwrap();
    unsafe {
        let status = pcai_delete_fs_item(path_cstr.as_ptr(), true);
        assert_eq!(status, PcaiStatus::Success);
    }
    assert!(!sub_dir.exists());
}

#[test]
fn test_pcai_replace_in_file_literal() {
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.txt");
    fs::write(&file_path, "Hello World").unwrap();

    let path = CString::new(file_path.to_str().unwrap()).unwrap();
    let pattern = CString::new("World").unwrap();
    let replacement = CString::new("Rust").unwrap();

    unsafe {
        let status = pcai_replace_in_file(
            path.as_ptr(),
            pattern.as_ptr(),
            replacement.as_ptr(),
            false, // not regex
            false, // no backup
        );
        assert_eq!(status, PcaiStatus::Success);
    }

    let content = fs::read_to_string(&file_path).unwrap();
    assert_eq!(content, "Hello Rust");
}

#[test]
fn test_pcai_replace_in_file_with_backup() {
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.txt");
    fs::write(&file_path, "Original").unwrap();

    let path = CString::new(file_path.to_str().unwrap()).unwrap();
    let pattern = CString::new("Original").unwrap();
    let replacement = CString::new("Modified").unwrap();

    unsafe {
        let status = pcai_replace_in_file(
            path.as_ptr(),
            pattern.as_ptr(),
            replacement.as_ptr(),
            false,
            true, // create backup
        );
        assert_eq!(status, PcaiStatus::Success);
    }

    let backup_path = format!("{}.bak", file_path.to_str().unwrap());
    assert!(std::path::Path::new(&backup_path).exists());
}

#[test]
fn test_pcai_delete_nonexistent() {
    let path = CString::new("/nonexistent/path/file.txt").unwrap();
    unsafe {
        let status = pcai_delete_fs_item(path.as_ptr(), false);
        assert_eq!(status, PcaiStatus::PathNotFound);
    }
}

#[test]
fn test_pcai_replace_in_file_regex() {
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.txt");
    fs::write(&file_path, "foo123bar456baz").unwrap();

    let path = CString::new(file_path.to_str().unwrap()).unwrap();
    let pattern = CString::new(r"\d+").unwrap(); // Match digits
    let replacement = CString::new("X").unwrap();

    unsafe {
        let status = pcai_replace_in_file(
            path.as_ptr(),
            pattern.as_ptr(),
            replacement.as_ptr(),
            true, // regex mode
            false,
        );
        assert_eq!(status, PcaiStatus::Success);
    }

    let content = fs::read_to_string(&file_path).unwrap();
    assert_eq!(content, "fooXbarXbaz");
}

#[test]
fn test_pcai_delete_empty_directory() {
    let temp_dir = TempDir::new().unwrap();
    let sub_dir = temp_dir.path().join("empty_dir");
    fs::create_dir(&sub_dir).unwrap();
    assert!(sub_dir.exists());

    let path_cstr = CString::new(sub_dir.to_str().unwrap()).unwrap();
    unsafe {
        let status = pcai_delete_fs_item(path_cstr.as_ptr(), false);
        assert_eq!(status, PcaiStatus::Success);
    }
    assert!(!sub_dir.exists());
}

#[test]
fn test_pcai_delete_null_pointer() {
    unsafe {
        let status = pcai_delete_fs_item(std::ptr::null(), false);
        assert_eq!(status, PcaiStatus::NullPointer);
    }
}

#[test]
fn test_pcai_replace_null_pointers() {
    unsafe {
        // Null file path
        let pattern = CString::new("test").unwrap();
        let replacement = CString::new("replacement").unwrap();
        let status = pcai_replace_in_file(
            std::ptr::null(),
            pattern.as_ptr(),
            replacement.as_ptr(),
            false,
            false,
        );
        assert_eq!(status, PcaiStatus::NullPointer);

        // Null pattern
        let path = CString::new("/tmp/test.txt").unwrap();
        let status = pcai_replace_in_file(
            path.as_ptr(),
            std::ptr::null(),
            replacement.as_ptr(),
            false,
            false,
        );
        assert_eq!(status, PcaiStatus::NullPointer);

        // Null replacement
        let status = pcai_replace_in_file(
            path.as_ptr(),
            pattern.as_ptr(),
            std::ptr::null(),
            false,
            false,
        );
        assert_eq!(status, PcaiStatus::NullPointer);
    }
}

#[test]
fn test_pcai_replace_nonexistent_file() {
    let path = CString::new("/nonexistent/file.txt").unwrap();
    let pattern = CString::new("test").unwrap();
    let replacement = CString::new("replacement").unwrap();

    unsafe {
        let status = pcai_replace_in_file(
            path.as_ptr(),
            pattern.as_ptr(),
            replacement.as_ptr(),
            false,
            false,
        );
        assert_eq!(status, PcaiStatus::PathNotFound);
    }
}

#[test]
fn test_pcai_replace_no_matches() {
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.txt");
    let original_content = "This is original content";
    fs::write(&file_path, original_content).unwrap();

    let path = CString::new(file_path.to_str().unwrap()).unwrap();
    let pattern = CString::new("nonexistent_pattern").unwrap();
    let replacement = CString::new("replacement").unwrap();

    unsafe {
        let status = pcai_replace_in_file(
            path.as_ptr(),
            pattern.as_ptr(),
            replacement.as_ptr(),
            false,
            false,
        );
        assert_eq!(status, PcaiStatus::Success);
    }

    // Content should remain unchanged
    let content = fs::read_to_string(&file_path).unwrap();
    assert_eq!(content, original_content);
}

#[test]
fn test_pcai_replace_multiple_occurrences() {
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.txt");
    fs::write(&file_path, "foo bar foo baz foo").unwrap();

    let path = CString::new(file_path.to_str().unwrap()).unwrap();
    let pattern = CString::new("foo").unwrap();
    let replacement = CString::new("qux").unwrap();

    unsafe {
        let status = pcai_replace_in_file(
            path.as_ptr(),
            pattern.as_ptr(),
            replacement.as_ptr(),
            false,
            false,
        );
        assert_eq!(status, PcaiStatus::Success);
    }

    let content = fs::read_to_string(&file_path).unwrap();
    assert_eq!(content, "qux bar qux baz qux");
}

// Note: String buffer operations are tested indirectly through pcai_replace_in_files

#[test]
fn test_pcai_replace_in_files_basic() {
    let temp_dir = TempDir::new().unwrap();

    // Create test files
    fs::write(temp_dir.path().join("file1.txt"), "Hello World").unwrap();
    fs::write(temp_dir.path().join("file2.txt"), "Hello Rust").unwrap();
    fs::write(temp_dir.path().join("file3.md"), "Hello There").unwrap();

    let root = CString::new(temp_dir.path().to_str().unwrap()).unwrap();
    let pattern = CString::new("*.txt").unwrap();
    let content_pattern = CString::new("Hello").unwrap();
    let replacement = CString::new("Goodbye").unwrap();

    unsafe {
        let buffer = pcai_replace_in_files(
            root.as_ptr(),
            pattern.as_ptr(),
            content_pattern.as_ptr(),
            replacement.as_ptr(),
            false,
            false,
        );

        // Verify we got a valid buffer
        assert!(!buffer.data.is_null());
        assert!(buffer.len > 0);

        // Parse JSON result
        let json_str = CString::from_raw(buffer.data).to_str().unwrap().to_string();
        let result: serde_json::Value = serde_json::from_str(&json_str).unwrap();

        assert_eq!(result["status"], "success");
        assert_eq!(result["files_scanned"], 2); // Only .txt files
        assert_eq!(result["files_changed"], 2);
        assert_eq!(result["matches_replaced"], 2);

        // Reconstruct to avoid double-free during test cleanup
        let _ = CString::new(json_str).unwrap().into_raw();
    }

    // Verify file contents
    let content1 = fs::read_to_string(temp_dir.path().join("file1.txt")).unwrap();
    assert_eq!(content1, "Goodbye World");

    let content2 = fs::read_to_string(temp_dir.path().join("file2.txt")).unwrap();
    assert_eq!(content2, "Goodbye Rust");

    // .md file should be unchanged
    let content3 = fs::read_to_string(temp_dir.path().join("file3.md")).unwrap();
    assert_eq!(content3, "Hello There");
}
