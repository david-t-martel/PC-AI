//! Integration tests for pcai-inference

#[cfg(test)]
mod tests {
    use pcai_inference::{backends::*, config::*, Error, Result};

    #[test]
    fn test_generate_request_serialization() {
        let req = GenerateRequest {
            prompt: "Test prompt".to_string(),
            max_tokens: Some(100),
            temperature: Some(0.7),
            top_p: Some(0.95),
            stop: vec!["STOP".to_string()],
        };

        let json = serde_json::to_string(&req).unwrap();
        let deserialized: GenerateRequest = serde_json::from_str(&json).unwrap();

        assert_eq!(req.prompt, deserialized.prompt);
        assert_eq!(req.max_tokens, deserialized.max_tokens);
    }

    #[test]
    fn test_config_defaults() {
        let defaults = GenerationDefaults::default();
        assert_eq!(defaults.max_tokens, 512);
        assert_eq!(defaults.temperature, 0.7);
        assert_eq!(defaults.top_p, 0.95);
    }

    #[cfg(feature = "server")]
    #[test]
    fn test_server_config_defaults() {
        let server = ServerConfig::default();
        assert_eq!(server.host, "127.0.0.1");
        assert_eq!(server.port, 8080);
        assert!(server.cors);
    }

    #[test]
    fn test_error_types() {
        let err = Error::ModelNotLoaded;
        assert_eq!(err.to_string(), "Model not loaded");

        let err = Error::Backend("test error".to_string());
        assert_eq!(err.to_string(), "Backend error: test error");
    }
}
