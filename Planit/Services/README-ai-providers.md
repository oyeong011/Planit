# AI Provider Integration

Planit routes chat requests through `AIService`. The current provider boundary is:

- Input: `systemPrompt`, `userMessage`, recent chat `history`, calendar context, and safe attachment paths or extracted PDF text.
- Output: plain assistant text, or JSON matching `AIResponseWithActions` with `message` and `actions`.
- Action handling: providers only suggest actions. `AIService` parses, validates, queues, and executes calendar or todo changes.

## Providers

`AIProvider` declares the UI label, icon, default model, CLI name, and session behavior.

- Claude Code: stateless. Uses `--no-session-persistence`.
- Codex: stateless. Uses `--ephemeral`.
- Hermes: stateful by design. Planit currently detects the `hermes` CLI and exposes the provider in UI, but real execution is intentionally stubbed until the Hermes command contract is finalized.

## Adding a Provider

1. Add a case to `AIProvider`.
2. Fill in `icon`, `defaultModel`, `cliName`, and `isStateful`.
3. Extend CLI availability storage in `AIService` or replace it with a keyed registry.
4. Add a `sendMessage` branch that returns raw assistant output compatible with `parseAIResponse`.
5. Keep `resolvePath(_:)` restricted to system-managed directories.
6. Add setup/settings strings and provider-contract tests.

## Adapter Direction

The current implementation still uses provider branches inside `sendMessage`. The next structural step should be a small adapter registry:

```swift
struct AIProviderRequest {
    let systemPrompt: String
    let userMessage: String
    let history: [ChatMessage]
    let imagePaths: [String]
}

protocol AIProviderAdapter {
    var provider: AIProvider { get }
    func complete(_ request: AIProviderRequest) async -> String
}
```

Claude and Codex adapters can wrap the existing CLI argument construction and `sendCLI` execution. Hermes should start as an adapter stub, then move to real execution once Planit chooses a session policy.

## Hermes Session Policy

Hermes keeps memory between sessions, unlike the current Claude and Codex calls. Planit should keep app state authoritative:

- `chatMessages` remains the visible conversation history.
- Calendar context is rebuilt or reused by `AIService`, not recovered from Hermes memory.
- Pending calendar actions stay in Planit until the user confirms them.
- A future Hermes conversation ID should be scoped to one Planit chat and reset when external context consent changes.

Until that policy is implemented, Hermes should not receive calendar context or attachments through a real CLI call.
