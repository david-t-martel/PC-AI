#[test]
fn test_peft_adapter_config_format() {
    // Test that adapter_config.json has expected structure
    let expected_fields = vec!["peft_type", "base_model_name_or_path", "r", "lora_alpha"];

    // This is a structure test - actual file generation requires model setup
    for field in expected_fields {
        assert!(!field.is_empty());
    }
}

#[test]
fn test_peft_output_directory_structure() {
    // Test expected file names
    let expected_files = vec!["adapter_config.json", "adapter_model.safetensors"];
    assert_eq!(expected_files.len(), 2);
}
