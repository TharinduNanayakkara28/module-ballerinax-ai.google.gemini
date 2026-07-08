// Copyright (c) 2026 WSO2 LLC (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;

# Configurations for controlling the behaviours when communicating with a remote HTTP endpoint.
@display {label: "Connection Configuration"}
public type ConnectionConfig record {|

    # The HTTP version understood by the client
    @display {label: "HTTP Version"}
    http:HttpVersion httpVersion = http:HTTP_2_0;

    # Configurations related to HTTP/1.x protocol
    @display {label: "HTTP1 Settings"}
    http:ClientHttp1Settings http1Settings?;

    # Configurations related to HTTP/2 protocol
    @display {label: "HTTP2 Settings"}
    http:ClientHttp2Settings http2Settings?;

    # The maximum time to wait (in seconds) for a response before closing the connection
    @display {label: "Timeout"}
    decimal timeout = 60;

    # The choice of setting `forwarded`/`x-forwarded` header
    @display {label: "Forwarded"}
    string forwarded = "disable";

    # Configurations associated with request pooling
    @display {label: "Pool Configuration"}
    http:PoolConfiguration poolConfig?;

    # HTTP caching related configurations
    @display {label: "Cache Configuration"}
    http:CacheConfig cache?;

    # Specifies the way of handling compression (`accept-encoding`) header
    @display {label: "Compression"}
    http:Compression compression = http:COMPRESSION_AUTO;

    # Configurations associated with the behaviour of the Circuit Breaker
    @display {label: "Circuit Breaker Configuration"}
    http:CircuitBreakerConfig circuitBreaker?;

    # Configurations associated with retrying
    @display {label: "Retry Configuration"}
    http:RetryConfig retryConfig?;

    # Configurations associated with inbound response size limits
    @display {label: "Response Limit Configuration"}
    http:ResponseLimitConfigs responseLimits?;

    # SSL/TLS-related options
    @display {label: "Secure Socket Configuration"}
    http:ClientSecureSocket secureSocket?;

    # Proxy server related options
    @display {label: "Proxy Configuration"}
    http:ProxyConfig proxy?;

    # Enables the inbound payload validation functionality which provided by the constraint package. Enabled by default
    @display {label: "Payload Validation"}
    boolean validation = true;
|};

# Text-generation (`:generateContent`) model types for Gemini.
# Reference: https://ai.google.dev/gemini-api/docs/models
# NOTE: Gemini's model lineup changes frequently. Verify these IDs against the live
# `/v1beta/models` listing for your API version; older deployments may still expose
# the 2.x line, and newer ones may add models not listed here. Non-text models
# (TTS/audio, image/video generation, embeddings) are intentionally excluded.
@display {label: "Gemini Model Names"}
public enum GEMINI_MODEL_NAMES {
    GEMINI_3_1_PRO_PREVIEW = "gemini-3.1-pro-preview",
    GEMINI_3_5_FLASH = "gemini-3.5-flash",
    GEMINI_3_FLASH_PREVIEW = "gemini-3-flash-preview",
    GEMINI_3_1_FLASH_LITE = "gemini-3.1-flash-lite",
    GEMINI_2_5_PRO = "gemini-2.5-pro",
    GEMINI_2_5_FLASH = "gemini-2.5-flash",
    GEMINI_2_5_FLASH_LITE = "gemini-2.5-flash-lite"
}

# Embedding (`:embedContent`) model types for Gemini.
# Reference: https://ai.google.dev/gemini-api/docs/embeddings
# NOTE: Verify against the live `/v1beta/models` listing before relying on these.
@display {label: "Gemini Embedding Model Names"}
public enum GEMINI_EMBEDDING_MODEL_NAMES {
    GEMINI_EMBEDDING_2 = "gemini-embedding-2",
    GEMINI_EMBEDDING_001 = "gemini-embedding-001"
}

// ── Gemini wire types (generateContent / streamGenerateContent) ─────────────
// Hand-written records modelling the subset of the Gemini `generateContent`
// REST API that this connector uses. Records consumed from responses are kept
// open (`record { }`) so that fields we do not model (e.g. safetyRatings,
// citationMetadata, avgLogprobs) are tolerated during binding rather than
// causing conversion failures.
// Reference: https://ai.google.dev/api/generate-content

# Inline binary data carried within a content part (e.g. an image), base64-encoded.
public type InlineData record {
    # IANA media type of the data, e.g. "image/png"
    string mimeType;
    # Base64-encoded bytes of the data
    string data;
};

# A function call requested by the model within a candidate part.
public type FunctionCall record {
    # Name of the function the model intends to call
    string name;
    # Structured arguments for the call, as a JSON object
    map<json> args?;
};

# The result of a tool/function execution, fed back to the model.
public type FunctionResponse record {
    # Name of the function that was executed
    string name;
    # The function's result payload, as a JSON object
    map<json> response;
};

# A single piece of content. A part holds exactly one of the optional members;
# the others are absent.
public type Part record {
    # Plain text content
    string text?;
    # Inline binary data (e.g. an image)
    InlineData inlineData?;
    # A function call requested by the model
    FunctionCall functionCall?;
    # A tool result supplied back to the model
    FunctionResponse functionResponse?;
};

# An ordered collection of parts attributed to a single role.
public type Content record {
    # Author of the content: "user" (input) or "model" (model output). Omitted
    # for `systemInstruction`.
    string role?;
    # The ordered parts that make up this content
    Part[] parts;
};

# Declares a function the model may call, described with a JSON-schema parameter object.
public type FunctionDeclaration record {
    # Function name
    string name;
    # Natural-language description of what the function does
    string description?;
    # JSON-schema object describing the function parameters
    map<json> parameters?;
};

# A group of tools made available to the model.
public type Tool record {
    # Function declarations the model may call
    FunctionDeclaration[] functionDeclarations?;
};

# Controls how the model selects functions to call.
public type FunctionCallingConfig record {
    # Calling mode: "AUTO" (model decides), "ANY" (must call a function),
    # or "NONE" (never call)
    string mode?;
    # When mode is "ANY", restricts the model to these function names
    string[] allowedFunctionNames?;
};

# Tool-related configuration for a request.
public type ToolConfig record {
    # Function-calling behaviour configuration
    FunctionCallingConfig functionCallingConfig?;
};

# Generation parameters controlling sampling and output shape.
public type GenerationConfig record {
    # Sampling temperature
    decimal temperature?;
    # Upper bound on tokens generated in the response
    int maxOutputTokens?;
    # Nucleus sampling threshold; tokens are considered until their cumulative
    # probability mass reaches this value
    decimal topP?;
    # Top-k sampling limit; sampling is restricted to the `topK` most probable tokens
    int topK?;
    # Sequences that, when produced, stop generation
    string[] stopSequences?;
    # Forces a response MIME type, e.g. "application/json" for structured output
    string responseMimeType?;
    # JSON schema the structured response must conform to (used with
    # `responseMimeType` = "application/json")
    map<json> responseSchema?;
};

# A single safety category/threshold pairing.
public type SafetySetting record {
    # Harm category, e.g. "HARM_CATEGORY_HARASSMENT"
    string category;
    # Blocking threshold, e.g. "BLOCK_NONE"
    string threshold;
};

# Request body for `:generateContent` and `:streamGenerateContent`.
public type GenerateContentRequest record {
    # The conversation contents, ordered oldest to newest
    Content[] contents;
    # System-level instruction applied to the whole request
    Content systemInstruction?;
    # Tools the model may use
    Tool[] tools?;
    # Tool-calling configuration
    ToolConfig toolConfig?;
    # Sampling and output configuration
    GenerationConfig generationConfig?;
    # Safety category thresholds
    SafetySetting[] safetySettings?;
};

# A single generated candidate within a response.
public type Candidate record {
    # The generated content
    Content content?;
    # Why generation stopped, e.g. "STOP", "MAX_TOKENS", "SAFETY"
    string finishReason?;
    # Index of this candidate in the list
    int index?;
};

# Token accounting for a request/response.
public type UsageMetadata record {
    # Tokens counted in the prompt
    int promptTokenCount?;
    # Tokens counted across all generated candidates
    int candidatesTokenCount?;
    # Total tokens (prompt + candidates)
    int totalTokenCount?;
};

# A safety rating for a single harm category.
public type SafetyRating record {
    # Harm category, e.g. "HARM_CATEGORY_HARASSMENT"
    string category?;
    # Assessed probability, e.g. "NEGLIGIBLE", "LOW", "MEDIUM", "HIGH"
    string probability?;
    # Whether the content was blocked due to this rating
    boolean blocked?;
};

# Feedback about the prompt itself, populated when Gemini returns no candidates
# because the prompt was blocked.
public type PromptFeedback record {
    # Reason the prompt was blocked, e.g. "SAFETY", "OTHER", "BLOCKLIST",
    # "PROHIBITED_CONTENT", "IMAGE_SAFETY"
    string blockReason?;
    # Per-category safety ratings for the prompt
    SafetyRating[] safetyRatings?;
};

# Response body for `:generateContent`.
public type GenerateContentResponse record {
    # Generated candidates; multiple only when more than one was requested
    Candidate[] candidates?;
    # Feedback about the prompt, including a block reason when the prompt is rejected
    PromptFeedback promptFeedback?;
    # Token accounting for the request
    UsageMetadata usageMetadata?;
    # The concrete model version that served the request
    string modelVersion?;
};

// ── Gemini embedding wire types (embedContent / batchEmbedContents) ─────────

# Request body for `:embedContent`.
public type EmbedContentRequest record {
    # The model resource name, e.g. "models/text-embedding-004"
    string model;
    # The content to embed
    Content content;
};

# An embedding vector.
public type ContentEmbedding record {
    # The embedding values
    float[] values;
};

# Response body for `:embedContent`.
public type EmbedContentResponse record {
    # The generated embedding
    ContentEmbedding embedding;
};

# Request body for `:batchEmbedContents`.
public type BatchEmbedContentsRequest record {
    # The individual embedding requests, one per input
    EmbedContentRequest[] requests;
};

# Response body for `:batchEmbedContents`.
public type BatchEmbedContentsResponse record {
    # The generated embeddings, in request order
    ContentEmbedding[] embeddings;
};
