# Inference Module Improvements Plan

**Date:** 2026-01-30
**Status:** ✅ Mostly complete (P3 docs pending)

## Overview

Critical improvements identified during code review of the pcai-inference testing framework.

## Parallel Execution Tracks

### Track A: CI/CD Fixes (P0) ✅
- [x] Fix `dtolnay/rust-action` → `dtolnay/rust-toolchain`
- [x] Add CUDA build variant job
- [x] Add test coverage reporting (cargo-llvm-cov + Codecov)
- [x] Add Rust version matrix testing (stable, 1.75, 1.80)

### Track B: PowerShell Compatibility (P0) ✅
- [x] Fix UTF8 string marshaling for PS 5.1 (.NET Framework compat)
- [x] Fix default DLL path (target/release → bin/)
- [x] Add module cleanup on Remove-Module (OnRemove handler)
- [x] Add DLL version checking (Test-PcaiDllVersion function)

### Track C: Test Infrastructure (P1) ✅
- [x] Extract shared test helpers to module (TestHelpers.psm1)
- [x] Add test discovery script (Invoke-AllTests.ps1)
- [x] Update all test files to use shared helpers

### Track D: Rust FFI Enhancements (P2) ✅
- [x] Add error code enum for structured errors (PcaiErrorCode)
- [x] Add input validation for prompt length (100KB limit)
- [x] Add pcai_version() FFI function
- [x] Add pcai_last_error_code() FFI function

### Track E: Documentation (P3)
- [ ] Add inline Rust doc tests
- [ ] Add troubleshooting guide (partial coverage exists in BUILD_REQUIREMENTS/FFI_IMPLEMENTATION/NATIVE_INFERENCE_INTEGRATION)
- [ ] Add performance baseline docs (preliminary benchmarks exist, no consolidated baseline)

## Files to Modify

| File | Track | Changes |
|------|-------|---------|
| `.github/workflows/rust-inference.yml` | A | Fix action, add CUDA job |
| `Modules/PcaiInference.psm1` | B | UTF8 compat, paths, cleanup |
| `Tests/Helpers/TestHelpers.psm1` | C | New shared module |
| `Deploy/pcai-inference/src/ffi/mod.rs` | D | Error codes, version |
| `Tests/Integration/FFI.Inference.Tests.ps1` | C | Use shared helpers |

## Success Criteria

- All CI jobs pass
- PowerShell 5.1 and 7.x compatibility
- No duplicated test helper code
- Structured error handling via FFI
