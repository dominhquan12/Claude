# UserPromptSubmit hook — English Coach reminder
# Detects English in the prompt and injects a reminder to apply 99-english-coach.md

# Read stdin as raw UTF-8 bytes to avoid Windows OEM pipe encoding issue
$stdin = [Console]::OpenStandardInput()
$reader = New-Object System.IO.StreamReader($stdin, [System.Text.Encoding]::UTF8)
$rawInput = $reader.ReadToEnd()

try {
    $data = $rawInput | ConvertFrom-Json
    $prompt = $data.prompt
} catch {
    exit 0
}

if (-not $prompt) { exit 0 }

# Detect English: match common English words (word-boundary, case-insensitive)
$hasEnglish = $prompt -match '\b(the|is|are|was|were|have|has|had|do|does|did|will|would|could|should|may|might|can|you|he|she|it|we|they|a|an|in|on|at|to|for|of|and|or|but|not|with|this|that|these|those|my|your|our|its|I)\b'

# Detect Vietnamese: any non-ASCII character (Vietnamese always has diacritics outside ASCII range)
$hasVietnamese = $prompt -match '[^\x00-\x7F]'

if ($hasEnglish -and -not $hasVietnamese) {
    @{
        hookSpecificOutput = @{
            hookEventName     = "UserPromptSubmit"
            additionalContext = "[English Coach] English detected. Apply rule 99-english-coach.md: Step 1 grammar check first, then Step 2 answer the question."
        }
    } | ConvertTo-Json -Compress | Write-Output
}

exit 0
