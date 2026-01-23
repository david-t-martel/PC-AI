# PC-AI.LLM.Tests.ps1 - Test Fixes Summary

## Overview
Fixed HIGH priority issues in the unit tests to match actual implementation behavior and return types.

## Issues Fixed

### 1. Get-LLMStatus String Matching on Object (Lines 29-30, 81)

**Problem**:
- Test used `$result | Should -Match "Running|OK|Available"`
- Actual implementation returns `PSCustomObject` with nested properties

**Fix**:
```powershell
# Before
$result | Should -Match "Running|OK|Available"

# After
$result.Ollama.Installed | Should -Be $true
$result.Ollama.ApiConnected | Should -Be $true
```

**Added**:
- Mock for `Test-Path` to simulate Ollama installation
- Comprehensive mock for `Invoke-RestMethod` to handle `/api/tags` endpoint
- New test context for "Ollama not installed" scenario
- Use of `-TestConnection` parameter for explicit API testing

### 2. Send-OllamaRequest Body Parameter Filter (Lines 102-104, 110-112, 145, 160)

**Problem**:
- Tests checked `$Body -match` with regex patterns for JSON
- Body parameter format was inconsistent with expectations

**Fix**:
```powershell
# Before
Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
    $Body -match '"model"\s*:\s*"llama3\.2:latest"'
}

# After
Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
    $Uri -match "/api/generate" -and $Body -like '*"model"*"llama3.2:latest"*'
}
```

**Changes**:
- Changed regex patterns to `-like` wildcards for simpler matching
- Added URI validation to ensure correct endpoint is called
- Mock now returns appropriate responses for `/api/tags` and `/api/generate` endpoints

### 3. Send-OllamaRequest Response Property Capitalization (Line 117)

**Problem**:
- Test expected `$result.response` (lowercase)
- Implementation returns `$result.Response` (uppercase)

**Fix**:
```powershell
# Before
$result.response | Should -Not -BeNullOrEmpty

# After
$result.Response | Should -Not -BeNullOrEmpty
```

### 4. Send-OllamaRequest Error Handling (Lines 129-130)

**Problem**:
- Test expected error object to be returned: `$result.error`
- Implementation throws exceptions instead

**Fix**:
```powershell
# Before
$result = Send-OllamaRequest -Prompt "Test" -Model "nonexistent:latest" -ErrorAction SilentlyContinue
$result.error | Should -Match "not found"

# After
{ Send-OllamaRequest -Prompt "Test" -Model "nonexistent:latest" -ErrorAction Stop } | Should -Throw -ExpectedMessage "*not available*"
```

### 5. Send-OllamaRequest Parameter Name (Line 151)

**Problem**:
- Test used `-SystemMessage` parameter
- Actual parameter is `-System`

**Fix**:
```powershell
# Before
Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest" -SystemMessage "You are a PC diagnostics expert"

# After
Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest" -System "You are a PC diagnostics expert"
```

### 6. Invoke-LLMChat Mock Misalignment (Lines 194-196, 212-214)

**Problem**:
- Tests mocked `Send-OllamaRequest`
- Implementation calls `Invoke-OllamaChat` (different function)

**Fix**:
```powershell
# Before
Mock Send-OllamaRequest {
    Get-MockOllamaResponse -Type Success
} -ModuleName PC-AI.LLM

# After
Mock Invoke-RestMethod {
    param($Uri)
    if ($Uri -match "/api/chat") {
        @{
            model = "llama3.2:latest"
            message = @{
                role = "assistant"
                content = "Hello! How can I help you?"
            }
            done = $true
        }
    }
} -ModuleName PC-AI.LLM
```

**Changes**:
- Mock `Invoke-RestMethod` directly to intercept `/api/chat` calls
- Return proper chat response structure with `message.content`
- Added `-Interactive` parameter to tests

### 7. Invoke-LLMChat Parameter Name (Line 252)

**Problem**:
- Test used `-SystemPrompt` parameter
- Actual parameter is `-System`

**Fix**:
```powershell
# Before
Invoke-LLMChat -Model "llama3.2:latest" -SystemPrompt "You are helpful"

# After
Invoke-LLMChat -Interactive -Model "llama3.2:latest" -System "You are helpful"
```

### 8. Invoke-PCDiagnosis Parameter Name (Lines 260, 268, etc.)

**Problem**:
- Tests used `-ReportPath` parameter
- Actual parameter is `-DiagnosticReportPath`

**Fix**:
```powershell
# Before
Invoke-PCDiagnosis -ReportPath "TestDrive:\report.txt"

# After
Invoke-PCDiagnosis -DiagnosticReportPath "TestDrive:\report.txt"
```

### 9. Invoke-PCDiagnosis Mock Misalignment (Lines 254, 270, etc.)

**Problem**:
- Tests mocked `Send-OllamaRequest`
- Implementation calls `Invoke-OllamaChat` via `Invoke-RestMethod`

**Fix**:
```powershell
# Before
Mock Send-OllamaRequest {
    Get-MockOllamaResponse -Type Success
} -ModuleName PC-AI.LLM

# After
Mock Invoke-RestMethod {
    param($Uri)
    if ($Uri -match "/api/chat") {
        @{
            model = "qwen2.5-coder:7b"
            message = @{
                role = "assistant"
                content = "Analysis complete. Found USB device error code 43."
            }
            done = $true
            eval_count = 500
        }
    }
} -ModuleName PC-AI.LLM
```

**Added**:
- Mock for `Get-Content` with conditional return based on file path
- Mock for `Test-Path` to simulate file existence
- Added `-SaveReport` parameter to save test

### 10. Set-LLMConfig Missing Get-LLMConfig (Line 362)

**Problem**:
- Test tried to call `Get-LLMConfig` which doesn't exist
- Used module introspection: `& (Get-Module PC-AI.LLM) { Get-LLMConfig }`

**Fix**:
```powershell
# Before
It "Should load existing config" {
    $result = & (Get-Module PC-AI.LLM) { Get-LLMConfig }
    $result | Should -Not -BeNullOrEmpty
}

# After
It "Should return current config with ShowConfig" {
    $result = Set-LLMConfig -ShowConfig
    $result | Should -Not -BeNullOrEmpty
    $result.PSObject.Properties.Name | Should -Contain "OllamaApiUrl"
    $result.PSObject.Properties.Name | Should -Contain "DefaultModel"
}
```

**Changes**:
- Replaced missing function call with `-ShowConfig` parameter
- Verified PSCustomObject properties directly
- Added new test context for `-Reset` parameter

### 11. Set-LLMConfig Mock Updates

**Problem**:
- Tests mocked `Set-Content`
- Implementation uses `Out-File`

**Fix**:
```powershell
# Before
Mock Set-Content {} -ModuleName PC-AI.LLM

# After
Mock Out-File {} -ModuleName PC-AI.LLM
```

## Test Coverage Improvements

### Added Test Contexts
1. **Get-LLMStatus**: "When Ollama is not installed"
2. **Set-LLMConfig**: "When showing current configuration"
3. **Set-LLMConfig**: "When resetting configuration"

### Enhanced Mocks
- All mocks now handle multiple API endpoints (`/api/tags`, `/api/generate`, `/api/chat`)
- Conditional mocks for file operations based on path patterns
- Proper PSCustomObject structure for all responses

## Test Results

### Before Fixes
- Multiple failures due to type mismatches
- String matching on objects
- Parameter name mismatches
- Missing mock implementations

### After Fixes
- Tests properly validate PSCustomObject properties
- Correct parameter names used throughout
- Comprehensive mocking of all API calls
- Proper error handling verification

## Key Patterns Applied

### 1. Property Access Pattern
```powershell
# Access nested properties on PSCustomObject
$result.Ollama.ApiConnected | Should -Be $true
$result.Ollama.Models[0].Name | Should -Be "llama3.2:latest"
```

### 2. Comprehensive Mock Pattern
```powershell
# Mock with conditional responses
Mock Invoke-RestMethod {
    param($Uri)
    if ($Uri -match "/api/tags") {
        Get-MockOllamaResponse -Type ModelList
    } elseif ($Uri -match "/api/generate") {
        Get-MockOllamaResponse -Type Success
    } else {
        Get-MockOllamaResponse -Type Status
    }
} -ModuleName PC-AI.LLM
```

### 3. Exception Testing Pattern
```powershell
# Test that exceptions are thrown
{ Send-OllamaRequest -Prompt "Test" -Model "nonexistent:latest" -ErrorAction Stop } |
    Should -Throw -ExpectedMessage "*not available*"
```

### 4. Parameter Filter Pattern
```powershell
# Validate both URI and body content
Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
    $Uri -match "/api/generate" -and $Body -like '*"model"*"llama3.2:latest"*'
}
```

## Verification

Run tests with:
```powershell
Invoke-Pester Tests/Unit/PC-AI.LLM.Tests.ps1 -Output Detailed
```

Expected results:
- All Get-LLMStatus tests passing
- All Send-OllamaRequest tests passing (except where Ollama service needs to be running)
- All Invoke-LLMChat tests passing
- All Invoke-PCDiagnosis tests passing
- All Set-LLMConfig tests passing

## Notes

- Tests now accurately reflect the actual implementation behavior
- Mock structures match the actual API response formats
- Parameter names align with function definitions
- Error handling is properly tested with exception expectations
