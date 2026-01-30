//! FFI exports for PowerShell integration
//!
//! This module provides a C-compatible FFI interface for calling the pcai-inference
//! library from PowerShell via P/Invoke.
//!
//! ## Thread Safety
//!
//! - Global state is protected by Mutex
//! - Runtime is created once and reused
//! - Errors are stored in thread-local storage
//!
//! ## Usage from PowerShell
//!
//! ```powershell
//! # Load the DLL
//! Add-Type -Path "pcai_inference.dll" -Namespace PCAI -Name Inference
//!
//! # Initialize with backend
//! [PCAI.Inference]::pcai_init("llamacpp")
//!
//! # Load model
//! [PCAI.Inference]::pcai_load_model("path/to/model.gguf", -1)
//!
//! # Generate text
//! $result = [PCAI.Inference]::pcai_generate("Hello", 100, 0.7)
//! $text = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($result)
//! [PCAI.Inference]::pcai_free_string($result)
//! ```

use std::cell::RefCell;
use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_void};
use std::sync::{Mutex, OnceLock};

use tokio::runtime::Runtime;

use crate::backends::{BackendType, GenerateRequest, InferenceBackend};
use crate::Error;

// ============================================================================
// Global State
// ============================================================================

/// Global state holding the runtime and backend
struct GlobalState {
    runtime: Runtime,
    backend: Option<Box<dyn InferenceBackend>>,
}

/// Global state instance (initialized once)
static GLOBAL_STATE: OnceLock<Mutex<GlobalState>> = OnceLock::new();

// Thread-local error storage
thread_local! {
    static LAST_ERROR: RefCell<Option<String>> = RefCell::new(None);
}

/// Initialize global state on first access
fn init_global_state() -> &'static Mutex<GlobalState> {
    GLOBAL_STATE.get_or_init(|| {
        let runtime = Runtime::new().expect("Failed to create Tokio runtime");
        Mutex::new(GlobalState {
            runtime,
            backend: None,
        })
    })
}

/// Thread-local storage definition

/// Set the last error for the current thread
fn set_last_error(err: impl Into<String>) {
    LAST_ERROR.with(|e| {
        *e.borrow_mut() = Some(err.into());
    });
}

/// Clear the last error for the current thread
fn clear_last_error() {
    LAST_ERROR.with(|e| {
        *e.borrow_mut() = None;
    });
}

/// Get a C string from a raw pointer, handling null safely
unsafe fn c_str_from_ptr<'a>(ptr: *const c_char) -> Result<&'a str, Error> {
    if ptr.is_null() {
        return Err(Error::InvalidInput("Null pointer".to_string()));
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|e| Error::InvalidInput(format!("Invalid UTF-8: {}", e)))
}

// ============================================================================
// FFI Exports
// ============================================================================

/// Initialize the inference backend
///
/// # Arguments
/// * `backend_name` - Backend to use: "llamacpp" or "mistralrs"
///
/// # Returns
/// * 0 on success
/// * -1 on error (check pcai_last_error)
///
/// # Safety
/// * `backend_name` must be a valid null-terminated C string
/// * Must be called before any other functions except pcai_last_error
#[no_mangle]
pub extern "C" fn pcai_init(backend_name: *const c_char) -> i32 {
    clear_last_error();

    // Parse backend name
    let backend_str = match unsafe { c_str_from_ptr(backend_name) } {
        Ok(s) => s,
        Err(e) => {
            set_last_error(format!("Invalid backend name: {}", e));
            return -1;
        }
    };

    // Determine backend type
    let backend_type = match backend_str.to_lowercase().as_str() {
        #[cfg(feature = "llamacpp")]
        "llamacpp" | "llama.cpp" | "llama_cpp" => BackendType::LlamaCpp,

        #[cfg(feature = "mistralrs-backend")]
        "mistralrs" | "mistral.rs" | "mistral_rs" => BackendType::MistralRs,

        _ => {
            set_last_error(format!("Unknown backend: {}", backend_str));
            return -1;
        }
    };

    // Initialize global state and create backend
    let state = init_global_state();
    let mut guard = match state.lock() {
        Ok(g) => g,
        Err(e) => {
            set_last_error(format!("Failed to lock state: {}", e));
            return -1;
        }
    };

    // Create backend
    let backend = match backend_type.create() {
        Ok(b) => b,
        Err(e) => {
            set_last_error(format!("Failed to create backend: {}", e));
            return -1;
        }
    };

    guard.backend = Some(backend);
    tracing::info!("Initialized backend: {}", backend_str);

    0
}

/// Load a model into the active backend
///
/// # Arguments
/// * `model_path` - Path to the model file (GGUF or SafeTensors)
/// * `gpu_layers` - Number of layers to offload to GPU (-1 = all, 0 = CPU only)
///
/// # Returns
/// * 0 on success
/// * -1 on error (check pcai_last_error)
///
/// # Safety
/// * `model_path` must be a valid null-terminated C string
/// * Must call pcai_init first
#[no_mangle]
pub extern "C" fn pcai_load_model(model_path: *const c_char, gpu_layers: i32) -> i32 {
    clear_last_error();

    // Parse model path
    let path_str = match unsafe { c_str_from_ptr(model_path) } {
        Ok(s) => s.to_string(),
        Err(e) => {
            set_last_error(format!("Invalid model path: {}", e));
            return -1;
        }
    };

    // Get global state
    let state = init_global_state();
    let mut guard = match state.lock() {
        Ok(g) => g,
        Err(e) => {
            set_last_error(format!("Failed to lock state: {}", e));
            return -1;
        }
    };

    // For llamacpp backend, we need to recreate it with the right gpu_layers config
    // This is a limitation of the current backend design - do this before loading
    #[cfg(feature = "llamacpp")]
    {
        if let Some(backend) = guard.backend.as_ref() {
            if backend.backend_name() == "llama.cpp" {
                use crate::backends::llamacpp::LlamaCppBackend;

                let n_gpu_layers = if gpu_layers < 0 {
                    u32::MAX // All layers
                } else {
                    gpu_layers as u32
                };

                let new_backend = LlamaCppBackend::with_config(n_gpu_layers, 8192, 2048);
                guard.backend = Some(Box::new(new_backend));
            }
        }
    }
    #[cfg(not(feature = "llamacpp"))]
    {
        let _ = gpu_layers; // Suppress unused warning
    }

    // Check backend exists
    if guard.backend.is_none() {
        set_last_error("Backend not initialized. Call pcai_init first.");
        return -1;
    }

    // Load the model (async operation, block on runtime)
    // Split mutable reference to satisfy borrow checker
    let GlobalState { runtime, backend } = &mut *guard;

    if let Some(backend) = backend {
        let result = runtime.block_on(async {
            backend.load_model(&path_str).await
        });

        match result {
            Ok(_) => {
                tracing::info!("Model loaded: {}", path_str);
                0
            }
            Err(e) => {
                set_last_error(format!("Failed to load model: {}", e));
                -1
            }
        }
    } else {
        set_last_error("Backend not initialized. Call pcai_init first.");
        -1
    }
}

/// Generate text from a prompt
///
/// # Arguments
/// * `prompt` - Input text prompt
/// * `max_tokens` - Maximum tokens to generate (0 = default 512)
/// * `temperature` - Sampling temperature (0.0 = greedy, 1.0 = creative)
///
/// # Returns
/// * Pointer to generated text (caller must free with pcai_free_string)
/// * null on error (check pcai_last_error)
///
/// # Safety
/// * `prompt` must be a valid null-terminated C string
/// * Caller must free the returned string with pcai_free_string
/// * Must call pcai_load_model first
#[no_mangle]
pub extern "C" fn pcai_generate(
    prompt: *const c_char,
    max_tokens: u32,
    temperature: f32,
) -> *mut c_char {
    clear_last_error();

    // Parse prompt
    let prompt_str = match unsafe { c_str_from_ptr(prompt) } {
        Ok(s) => s,
        Err(e) => {
            set_last_error(format!("Invalid prompt: {}", e));
            return std::ptr::null_mut();
        }
    };

    // Get global state
    let state = init_global_state();
    let guard = match state.lock() {
        Ok(g) => g,
        Err(e) => {
            set_last_error(format!("Failed to lock state: {}", e));
            return std::ptr::null_mut();
        }
    };

    // Check backend exists
    let backend = match guard.backend.as_ref() {
        Some(b) => b,
        None => {
            set_last_error("Backend not initialized. Call pcai_init first.");
            return std::ptr::null_mut();
        }
    };

    // Check model loaded
    if !backend.is_loaded() {
        set_last_error("Model not loaded. Call pcai_load_model first.");
        return std::ptr::null_mut();
    }

    // Build request
    let request = GenerateRequest {
        prompt: prompt_str.to_string(),
        max_tokens: if max_tokens > 0 {
            Some(max_tokens as usize)
        } else {
            None
        },
        temperature: if temperature > 0.0 {
            Some(temperature)
        } else {
            None
        },
        top_p: None,
        stop: vec![],
    };

    // Generate (async operation, block on runtime)
    let result = guard.runtime.block_on(async {
        backend.generate(request).await
    });

    match result {
        Ok(response) => {
            tracing::debug!("Generated {} tokens", response.tokens_generated);

            // Convert to C string
            match CString::new(response.text) {
                Ok(c_str) => c_str.into_raw(),
                Err(e) => {
                    set_last_error(format!("Failed to create C string: {}", e));
                    std::ptr::null_mut()
                }
            }
        }
        Err(e) => {
            set_last_error(format!("Generation failed: {}", e));
            std::ptr::null_mut()
        }
    }
}

/// Callback function type for streaming generation
///
/// # Arguments
/// * `token` - Generated token text (null-terminated C string)
/// * `user_data` - User-provided data pointer
///
/// # Safety
/// * Callback must not panic
/// * Callback must not call back into pcai functions
pub type TokenCallback = extern "C" fn(token: *const c_char, user_data: *mut c_void);

/// Generate text with streaming callback
///
/// # Arguments
/// * `prompt` - Input text prompt
/// * `max_tokens` - Maximum tokens to generate (0 = default 512)
/// * `temperature` - Sampling temperature (0.0 = greedy, 1.0 = creative)
/// * `callback` - Function to call for each generated token
/// * `user_data` - Pointer to pass to callback
///
/// # Returns
/// * 0 on success
/// * -1 on error (check pcai_last_error)
///
/// # Safety
/// * `prompt` must be a valid null-terminated C string
/// * `callback` must be a valid function pointer
/// * `user_data` can be null
/// * Callback must not call back into pcai functions
/// * Must call pcai_load_model first
#[no_mangle]
#[allow(unused_variables)] // Some parameters unused without llamacpp feature
pub extern "C" fn pcai_generate_streaming(
    prompt: *const c_char,
    max_tokens: u32,
    temperature: f32,
    callback: TokenCallback,
    user_data: *mut c_void,
) -> i32 {
    clear_last_error();

    // Parse prompt
    let prompt_str = match unsafe { c_str_from_ptr(prompt) } {
        Ok(s) => s.to_string(),
        Err(e) => {
            set_last_error(format!("Invalid prompt: {}", e));
            return -1;
        }
    };

    // Get global state
    let state = init_global_state();
    let guard = match state.lock() {
        Ok(g) => g,
        Err(e) => {
            set_last_error(format!("Failed to lock state: {}", e));
            return -1;
        }
    };

    // Check backend exists
    let backend = match guard.backend.as_ref() {
        Some(b) => b,
        None => {
            set_last_error("Backend not initialized. Call pcai_init first.");
            return -1;
        }
    };

    // Check model loaded
    if !backend.is_loaded() {
        set_last_error("Model not loaded. Call pcai_load_model first.");
        return -1;
    }

    // Check if backend supports streaming
    // Currently only llamacpp has generate_streaming
    #[cfg(feature = "llamacpp")]
    if backend.backend_name() == "llama.cpp" {
        use crate::backends::llamacpp::LlamaCppBackend;

        // Build request
        let request = GenerateRequest {
            prompt: prompt_str,
            max_tokens: if max_tokens > 0 {
                Some(max_tokens as usize)
            } else {
                None
            },
            temperature: if temperature > 0.0 {
                Some(temperature)
            } else {
                None
            },
            top_p: None,
            stop: vec![],
        };

        // Downcast to LlamaCppBackend to access streaming method
        // SAFETY: We just checked backend_name() == "llama.cpp"
        let backend_ptr = backend.as_ref() as *const dyn InferenceBackend as *const LlamaCppBackend;
        let llamacpp_backend = unsafe { &*backend_ptr };

        // Generate with streaming
        let result = guard.runtime.block_on(async {
            llamacpp_backend.generate_streaming(request, |token| {
                // Convert token to C string and call callback
                if let Ok(c_token) = CString::new(token) {
                    callback(c_token.as_ptr(), user_data);
                }
            }).await
        });

        match result {
            Ok(response) => {
                tracing::debug!("Streaming completed: {} tokens", response.tokens_generated);
                return 0;
            }
            Err(e) => {
                set_last_error(format!("Streaming generation failed: {}", e));
                return -1;
            }
        }
    }

    // Fallback: streaming not supported
    set_last_error(format!(
        "Streaming not supported for backend: {}. Use pcai_generate instead.",
        backend.backend_name()
    ));
    -1
}

/// Free a string returned by pcai_generate
///
/// # Arguments
/// * `s` - String pointer returned by pcai_generate
///
/// # Safety
/// * `s` must be a pointer returned by pcai_generate or null
/// * Must not be called twice on the same pointer
#[no_mangle]
pub extern "C" fn pcai_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }

    unsafe {
        let _ = CString::from_raw(s);
    }
}

/// Shutdown the inference engine and free resources
///
/// # Safety
/// * After calling this, all other functions will fail until pcai_init is called again
#[no_mangle]
pub extern "C" fn pcai_shutdown() {
    clear_last_error();

    let state = init_global_state();
    let mut guard = match state.lock() {
        Ok(g) => g,
        Err(e) => {
            set_last_error(format!("Failed to lock state: {}", e));
            return;
        }
    };

    if let Some(mut backend) = guard.backend.take() {
        // Unload model
        let _ = guard.runtime.block_on(async {
            backend.unload_model().await
        });

        tracing::info!("Backend shutdown");
    }
}

/// Get the last error message for the current thread
///
/// # Returns
/// * Pointer to error message (do NOT free)
/// * null if no error
///
/// # Safety
/// * Returned pointer is valid until the next call to any pcai function
/// * Do NOT call pcai_free_string on this pointer
#[no_mangle]
pub extern "C" fn pcai_last_error() -> *const c_char {
    LAST_ERROR.with(|e| {
        let err_ref = e.borrow();
        match err_ref.as_ref() {
            Some(err) => {
                // SAFETY: We need to return a stable pointer that lives beyond this function.
                // We leak a CString to ensure it stays alive. This is acceptable for error
                // messages as they are infrequent and small.
                match CString::new(err.as_str()) {
                    Ok(c_str) => {
                        let ptr = c_str.as_ptr();
                        std::mem::forget(c_str); // Leak to keep alive
                        ptr
                    }
                    Err(_) => std::ptr::null(),
                }
            }
            None => std::ptr::null(),
        }
    })
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_storage() {
        clear_last_error();
        assert!(pcai_last_error().is_null());

        set_last_error("test error");
        let err_ptr = pcai_last_error();
        assert!(!err_ptr.is_null());

        let err_str = unsafe { CStr::from_ptr(err_ptr) };
        assert_eq!(err_str.to_str().unwrap(), "test error");

        clear_last_error();
        // Note: previous pointer may still be valid (leaked), but new call should return null
    }

    #[test]
    fn test_init_null_backend() {
        let result = pcai_init(std::ptr::null());
        assert_eq!(result, -1);
        assert!(!pcai_last_error().is_null());
    }

    #[test]
    fn test_generate_before_init() {
        // Reset state by calling shutdown
        pcai_shutdown();

        let prompt = CString::new("test").unwrap();
        let result = pcai_generate(prompt.as_ptr(), 10, 0.7);
        assert!(result.is_null());
        assert!(!pcai_last_error().is_null());
    }
}
