# Security and Lint Report - 2026-01-28

## Executive Summary

| Category | Status | Count |
|----------|--------|-------|
| Dependabot Alerts | 1 Open | High severity |
| Rust Clippy | ✅ Passing | 8 doc warnings |
| C# Build | ✅ Clean | 0 warnings |
| PowerShell | N/A | PSScriptAnalyzer not installed |

---

## 1. Dependabot Security Alerts

### Open Alert: protobuf JSON recursion bypass

| Field | Value |
|-------|-------|
| **Alert #** | 1 |
| **Severity** | High |
| **Package** | protobuf |
| **Vulnerable** | <= 6.33.4 |
| **Patched** | None available |
| **Status** | OPEN |

**Summary**: protobuf is affected by a JSON recursion depth bypass vulnerability. An attacker can craft a message with deeply nested `Any` fields that bypasses recursion depth limits when using `json_format.ParseDict()`.

**Impact**: Denial of Service via CPU exhaustion when parsing malicious JSON input.

**Mitigation**:
- No patched version available yet
- Monitor for protobuf updates
- Validate input before parsing JSON with nested Any fields
- Consider rate limiting JSON parsing endpoints

**Affected Dependencies** (transitive):
- google-ai-generativelanguage
- tensorboard
- vllm
- unsloth
- Various ML training dependencies

### Fixed Alerts

| # | Package | CVE | Fixed Version |
|---|---------|-----|---------------|
| 2 | System.Text.Json | CVE-2024-30105 | 8.0.4 |
| 3 | System.Text.Json | CVE-2024-43485 | 8.0.5 |

---

## 2. Rust Clippy Results

### Fixes Applied (commit c32d6cb)

| Issue | File | Fix |
|-------|------|-----|
| Unresolved import `tempfile` | 4 test files | Added dev-dependency |
| Raw pointer deref not unsafe | 19 FFI functions | Added crate-level allow |
| Boolean logic bug | path.rs:120 | Simplified condition |
| Unused imports | hash.rs | Removed c_char, PcaiStringBuffer |
| Redundant field name | usb.rs:73 | Changed `hardware_id: hardware_id` → `hardware_id` |
| Impl can be derived | error.rs | Added `#[derive(Default)]` |
| Dead code warnings | vmm_health.rs | Added `#[allow(dead_code)]` |
| Unnecessary cast | vmm_health.rs:72 | Removed `as i32` |
| map_or simplification | Multiple | Applied auto-fix |
| div_ceil pattern | tokenizer.rs | Used `.div_ceil()` |

### Remaining Warnings (8)

All are `missing_safety_doc` for unsafe FFI functions:
- `string.rs:68` - c_str_to_rust
- `performance/mod.rs:20` - pcai_get_system_summary_json
- `performance/mod.rs:40` - pcai_get_memory_details_json
- `performance/mod.rs:76` - pcai_get_top_processes_json

**Recommendation**: Add `# Safety` documentation sections to these functions.

---

## 3. C# Build Status

```
PcaiNative build: SUCCESS
Warnings: 0
Errors: 0
```

All P/Invoke bindings are up to date with the consolidated Rust DLL.

---

## 4. Remaining Development Gaps

### CargoTools Module (PowerShell)
- [ ] Test coverage ~20% → target 85%
- [ ] Add ShouldProcess for -Force operations
- [ ] Split Environment.ps1 (7 concerns)
- [ ] Implement Invoke-CargoAudit
- [ ] Implement Invoke-CargoExpand
- [ ] Implement Invoke-CargoBloat

### Rust FunctionGemma
- [ ] OpenAI Chat Completions endpoint (P0)
- [ ] Router prompt format support (P0)
- [ ] Dataset generator matching Python (P0)
- [ ] LoRA/QLoRA training support (P0)
- [ ] PowerShell wrapper for router

### pcai_core_lib
- [ ] Add `# Safety` docs to 4 unsafe functions
- [ ] Consider factoring complex type in hash.rs:96

---

## 5. Recommended Actions

### Immediate
1. Monitor protobuf for security patch
2. Add `# Safety` docs to remaining unsafe functions

### Short-term
1. Increase CargoTools test coverage
2. Complete FunctionGemma OpenAI endpoint
3. Install PSScriptAnalyzer for PowerShell linting

### Long-term
1. Implement remaining CargoTools debugging commands
2. Complete Rust FunctionGemma training pipeline
3. Add CI/CD integration for automated lint checks
