# Change Log

This file documents all significant changes made to the Ballerina `ai.google.gemini` package across releases.

## [Un-released]

### Added
- Initial implementation of the Gemini connector for the `ballerina/ai` framework.
  - `ModelProvider` — `chat` and structured `generate` backed by Gemini's `:generateContent` REST API.
  - `EmbeddingProvider` — `embed` and `batchEmbed` backed by `:embedContent` / `:batchEmbedContents`.
  - Native function calling (tool use) and structured output through Gemini's standard-JSON-Schema
    fields (`parametersJsonSchema` / `responseJsonSchema`), which accept `$ref`, `$defs`,
    `additionalProperties` and `prefixItems` without modification.
  - Gemini 3 thought signatures preserved across tool-call round trips, including parallel calls,
    which the API requires when a model turn is replayed in the conversation history.
  - Multimodal input through `generate` — images, PDFs, and Gemini File API references.
  - API-key authentication via the `x-goog-api-key` header.
- Streaming support, completing the `ai:ModelProvider` contract.
  - `chatStream` — streams `ai:ChatCompletionChunk` values over Gemini's
    `:streamGenerateContent?alt=sse` endpoint, normalizing candidates, tool calls, finish
    reasons and token usage onto the provider-agnostic shape.
  - `generateStream` — streams the generated answer as text fragments. Only `string` is
    supported; other expected types are rejected, since a partial generation is a
    meaningful value only for `string`.
  - Gemini's `"STOP"` finish reason is reported as `tool_calls` when the turn ends in a
    function call, so an agent loop does not mistake a pending tool call for a final answer.
  - Thought signatures are preserved on streamed tool calls, so a streamed model turn can be
    replayed in the conversation history on Gemini 3 models.
  - Chain-of-thought parts are surfaced through `delta.reasoning` rather than being folded
    into the answer text.
  - A failure the API reports mid-stream — an `{"error": ...}` frame on an already-2xx
    stream, a prompt rejected by the safety filters, or an unparseable frame — ends the
    stream with a typed `ai:Error` instead of being skipped, which would have truncated the
    answer and reported it as a normal completion.
  - Streamed calls open an `observe:ChatSpan` like `chat` does, carrying prompts, tools,
    token usage and the finish reason; the iterator closes it when the stream ends.
  - The SSE stream and its connection are released when a stream ends in failure, and a
    stream that has already ended is not read again.
  - The role is reported on the first delta only, as the normalized contract describes,
    rather than on every chunk as Gemini sends it.
