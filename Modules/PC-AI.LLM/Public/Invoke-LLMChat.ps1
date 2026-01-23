#Requires -Version 5.1

function Invoke-LLMChat {
    <#
    .SYNOPSIS
        Interactive chat interface with Ollama LLM

    .DESCRIPTION
        Provides a conversational interface with Ollama models, maintaining conversation history
        and supporting system prompts. Can run in interactive mode or single-shot mode.

    .PARAMETER Message
        The user message to send. If not provided in interactive mode, prompts for input.

    .PARAMETER Model
        The model to use for chat (default: qwen2.5-coder:7b)

    .PARAMETER System
        System prompt to set the assistant's behavior and context

    .PARAMETER Temperature
        Controls randomness (0.0-2.0). Lower = more deterministic. Default: 0.7

    .PARAMETER MaxTokens
        Maximum tokens to generate per response

    .PARAMETER Interactive
        Run in interactive mode with continuous conversation

    .PARAMETER History
        Existing conversation history to continue from

    .EXAMPLE
        Invoke-LLMChat -Message "What is PowerShell?"
        Sends a single message and returns response

    .EXAMPLE
        Invoke-LLMChat -Interactive -Model "qwen2.5-coder:7b" -System "You are a PowerShell expert"
        Starts interactive chat session with custom system prompt

    .EXAMPLE
        $history = Invoke-LLMChat -Message "Hello" -PassThru
        Invoke-LLMChat -Message "Tell me more" -History $history
        Continues conversation with maintained history

    .OUTPUTS
        PSCustomObject with response and conversation history
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0, ValueFromPipeline)]
        [string]$Message,

        [Parameter()]
        [string]$Model = $script:ModuleConfig.DefaultModel,

        [Parameter()]
        [string]$System,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [double]$Temperature = 0.7,

        [Parameter()]
        [ValidateRange(1, 100000)]
        [int]$MaxTokens,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [array]$History = @()
    )

    begin {
        Write-Verbose "Initializing chat session..."

        # Verify Ollama connectivity
        if (-not (Test-OllamaConnection)) {
            throw "Cannot connect to Ollama API. Ensure Ollama is running."
        }

        # Initialize conversation history
        $conversationHistory = [System.Collections.ArrayList]::new()

        # Add system message if provided
        if ($System) {
            [void]$conversationHistory.Add(@{
                role = 'system'
                content = $System
            })
        }

        # Add existing history
        foreach ($msg in $History) {
            [void]$conversationHistory.Add($msg)
        }
    }

    process {
        if ($Interactive) {
            Write-Host "`nStarting interactive chat session with $Model" -ForegroundColor Cyan
            Write-Host "Type 'exit', 'quit', or 'q' to end the session" -ForegroundColor Gray
            Write-Host "Type 'clear' to reset conversation history" -ForegroundColor Gray
            Write-Host "Type 'history' to view conversation history" -ForegroundColor Gray
            Write-Host ("-" * 60) -ForegroundColor Gray

            $continueChat = $true

            while ($continueChat) {
                # Get user input
                Write-Host "`nYou: " -NoNewline -ForegroundColor Green
                $userInput = Read-Host

                # Handle special commands
                switch ($userInput.ToLower().Trim()) {
                    { $_ -in @('exit', 'quit', 'q') } {
                        $continueChat = $false
                        Write-Host "`nChat session ended." -ForegroundColor Cyan
                        break
                    }
                    'clear' {
                        $conversationHistory.Clear()
                        if ($System) {
                            [void]$conversationHistory.Add(@{
                                role = 'system'
                                content = $System
                            })
                        }
                        Write-Host "Conversation history cleared." -ForegroundColor Yellow
                        continue
                    }
                    'history' {
                        Write-Host "`nConversation History:" -ForegroundColor Cyan
                        for ($i = 0; $i -lt $conversationHistory.Count; $i++) {
                            $msg = $conversationHistory[$i]
                            $roleColor = switch ($msg.role) {
                                'system' { 'Magenta' }
                                'user' { 'Green' }
                                'assistant' { 'Blue' }
                                default { 'White' }
                            }
                            Write-Host "[$($msg.role)]:" -ForegroundColor $roleColor -NoNewline
                            Write-Host " $($msg.content)"
                        }
                        continue
                    }
                }

                if ([string]::IsNullOrWhiteSpace($userInput)) {
                    continue
                }

                # Add user message to history
                [void]$conversationHistory.Add(@{
                    role = 'user'
                    content = $userInput
                })

                # Send request
                try {
                    Write-Host "Assistant: " -NoNewline -ForegroundColor Blue

                    $params = @{
                        Messages = $conversationHistory.ToArray()
                        Model = $Model
                        Temperature = $Temperature
                    }

                    if ($PSBoundParameters.ContainsKey('MaxTokens')) {
                        $params['MaxTokens'] = $MaxTokens
                    }

                    $response = Invoke-OllamaChat @params

                    $assistantMessage = $response.message.content
                    Write-Host $assistantMessage -ForegroundColor Blue

                    # Add assistant response to history
                    [void]$conversationHistory.Add(@{
                        role = 'assistant'
                        content = $assistantMessage
                    })
                }
                catch {
                    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
                    # Remove the failed user message from history
                    $conversationHistory.RemoveAt($conversationHistory.Count - 1)
                }
            }

            # Return final conversation state
            return [PSCustomObject]@{
                Model = $Model
                MessageCount = $conversationHistory.Count
                History = $conversationHistory.ToArray()
                Timestamp = Get-Date
            }
        }
        else {
            # Single-shot mode
            if ([string]::IsNullOrWhiteSpace($Message)) {
                throw "Message parameter is required in non-interactive mode"
            }

            # Add user message
            [void]$conversationHistory.Add(@{
                role = 'user'
                content = $Message
            })

            try {
                $params = @{
                    Messages = $conversationHistory.ToArray()
                    Model = $Model
                    Temperature = $Temperature
                }

                if ($PSBoundParameters.ContainsKey('MaxTokens')) {
                    $params['MaxTokens'] = $MaxTokens
                }

                $response = Invoke-OllamaChat @params

                $assistantMessage = $response.message.content

                # Add assistant response to history
                [void]$conversationHistory.Add(@{
                    role = 'assistant'
                    content = $assistantMessage
                })

                return [PSCustomObject]@{
                    Response = $assistantMessage
                    Model = $Model
                    MessageCount = $conversationHistory.Count
                    History = $conversationHistory.ToArray()
                    TotalDuration = $response.total_duration
                    LoadDuration = $response.load_duration
                    PromptEvalCount = $response.prompt_eval_count
                    EvalCount = $response.eval_count
                    Timestamp = Get-Date
                }
            }
            catch {
                Write-Error "Chat request failed: $_"
                throw
            }
        }
    }

    end {
        Write-Verbose "Chat session completed"
    }
}
