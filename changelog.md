# Change Log

This file documents all significant changes made to the Ballerina `ai.google.gemini` package across releases.

## [Unreleased]

### Added
- Initial implementation of the Gemini connector for the `ballerina/ai` framework.
  - `ModelProvider` — `chat` and structured `generate` backed by Gemini's `:generateContent` REST API.
  - `EmbeddingProvider` — `embed` and `batchEmbed` backed by `:embedContent` / `:batchEmbedContents`.
  - Native function calling (tool use) and native JSON-mode structured output (`responseMimeType` + `responseSchema`).
  - API-key authentication via the `x-goog-api-key` header.
  - Streaming (`chatStream` / `generateStream`) is intentionally not included in this release.
