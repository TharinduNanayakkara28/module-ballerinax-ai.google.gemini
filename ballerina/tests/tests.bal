// Copyright (c) 2026 WSO2 LLC. (http://www.wso2.org).
//
// WSO2 Inc. licenses this file to you under the Apache License,
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

import ballerina/ai;
import ballerina/test;

const SERVICE_URL = "http://localhost:8080/llm";
const API_KEY = "not-a-real-api-key";
const INLINE_IMAGE_ONLY_ERROR = "Only inline image data";
const UNSUPPORTED_DOC_ERROR = "Only text and image documents are supported.";

final ModelProvider provider = check new (API_KEY, GEMINI_2_5_FLASH, SERVICE_URL);
final EmbeddingProvider embeddingProvider = check new (API_KEY, GEMINI_EMBEDDING_001, SERVICE_URL);

// ── chat ───────────────────────────────────────────────────────────────────

@test:Config
function testChatWithTextResponse() returns ai:Error? {
    ai:ChatAssistantMessage result = check provider->chat([{role: ai:USER, content: "Say hello"}], []);
    test:assertEquals(result.content, "Hello there!");
}

@test:Config
function testChatWithToolCall() returns ai:Error? {
    ai:ChatCompletionFunctions weatherTool = {
        name: "getWeather",
        description: "Get the weather for a city",
        parameters: {"type": "object", "properties": {"city": {"type": "string"}}}
    };
    ai:ChatAssistantMessage result =
        check provider->chat([{role: ai:USER, content: "What's the weather in Colombo?"}], [weatherTool]);
    ai:FunctionCall[]? toolCalls = result.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[], "expected tool calls in the response");
    test:assertEquals((<ai:FunctionCall[]>toolCalls)[0].name, "getWeather");
}

@test:Config
function testChatWithoutTools() returns ai:Error? {
    // `tools` defaults to [] when omitted (no tools passed).
    ai:ChatAssistantMessage result = check provider->chat([{role: ai:USER, content: "Say hello"}]);
    test:assertEquals(result.content, "Hello there!");
    test:assertTrue(result.toolCalls is (), "expected no tool calls when no tools are provided");
}

@test:Config
function testChatWithMultipleTools() returns ai:Error? {
    ai:ChatCompletionFunctions weatherTool = {
        name: "getWeather",
        description: "Get the weather for a city",
        parameters: {"type": "object", "properties": {"city": {"type": "string"}}}
    };
    ai:ChatCompletionFunctions timeTool = {
        name: "getTime",
        description: "Get the current time for a city",
        parameters: {"type": "object", "properties": {"city": {"type": "string"}}}
    };
    ai:ChatAssistantMessage result =
        check provider->chat([{role: ai:USER, content: "What's the weather using two tools in Colombo?"}],
            [weatherTool, timeTool]);
    ai:FunctionCall[]? toolCalls = result.toolCalls;
    test:assertTrue(toolCalls is ai:FunctionCall[], "expected a tool call in the response");
    test:assertEquals((<ai:FunctionCall[]>toolCalls)[0].name, "getWeather");
}

@test:Config
function testChatWithSystemMessage() returns ai:Error? {
    ai:ChatAssistantMessage result = check provider->chat([
        {role: ai:SYSTEM, content: "You are a helpful assistant."},
        {role: ai:USER, content: "System check please"}
    ], []);
    test:assertEquals(result.content, "System instruction received.");
}

@test:Config
function testChatMultiTurnToolConversation() returns ai:Error? {
    ai:ChatMessage[] messages = [
        {role: ai:USER, content: "Weather follow-up for Paris"},
        {role: ai:ASSISTANT, toolCalls: [{name: "getWeather", arguments: {city: "Paris"}}]},
        {role: "function", name: "getWeather", content: "{\"temperature\": 20}"}
    ];
    ai:ChatAssistantMessage result = check provider->chat(messages, []);
    test:assertEquals(result.content, "It is 20 degrees in Paris.");
}

@test:Config
function testChatSanitizesToolSchema() returns ai:Error? {
    ai:ChatCompletionFunctions tool = {
        name: "getWeather",
        description: "Get the weather for a city",
        parameters: {
            "$schema": "http://json-schema.org/draft-07/schema#",
            "title": "WeatherParams",
            "$ref": "#/$defs/City",
            "default": {},
            "additionalProperties": false,
            "type": "object",
            "properties": {"city": {"type": "string", "default": "Colombo"}}
        }
    };
    ai:ChatAssistantMessage result =
        check provider->chat([{role: ai:USER, content: "Sanitize schema test"}], [tool]);
    test:assertTrue(result.toolCalls is ai:FunctionCall[], "expected a tool call in the response");
}

@test:Config
function testChatWithStopSequence() returns ai:Error? {
    ai:ChatAssistantMessage result =
        check provider->chat([{role: ai:USER, content: "Stop test"}], [], "END");
    test:assertEquals(result.content, "Stopping now.");
}

// ── generate (structured output) ─────────────────────────────────────────────

@test:Config
function testGenerateBasicReturnType() returns ai:Error? {
    int rating = check provider->generate(`Rate this blog out of 10.
        Title: ${blog1.title}
        Content: ${blog1.content}`);
    test:assertEquals(rating, 4);
}

@test:Config
function testGenerateArrayReturnType() returns ai:Error? {
    int[] ratings = check provider->generate(`Evaluate these blogs out of 10.
        Content: ${blog1.content}`);
    test:assertEquals(ratings, [9, 1]);
}

@test:Config
function testGenerateRecordReturnType() returns error? {
    Review result = check provider->generate(`Please rate this blog out of 10.
        Content: ${blog2.content}`);
    test:assertEquals(result, reviewRecord);
}

@test:Config
function testGenerateStringReturnType() returns error? {
    string joke = check provider->generate(`Give me a random joke`);
    test:assertEquals(joke, "Why did the chicken cross the road?");
}

@test:Config
function testGenerateForwardsGenerationConfig() returns ai:Error? {
    // The mock asserts temperature/maxOutputTokens/responseMimeType are present.
    int result = check provider->generate(`Config check: rate this out of 10`);
    test:assertEquals(result, 5);
}

@test:Config
function testGenerateWithTextDocument() returns ai:Error? {
    ai:TextDocument blog = {content: string `Title: ${blog1.title} Content: ${blog1.content}`};
    int rating = check provider->generate(`How would you rate this blog content out of 10. ${blog}.`);
    test:assertEquals(rating, 4);
}

@test:Config
function testGenerateWithTextChunk() returns ai:Error? {
    ai:TextChunk chunk = {content: string `Title: ${blog1.title} Content: ${blog1.content}`};
    int rating = check provider->generate(`How would you rate this text chunk out of 10. ${chunk}.`);
    test:assertEquals(rating, 4);
}

@test:Config
function testGenerateWithInlineImage() returns ai:Error? {
    ai:ImageDocument img = {content: sampleBinaryData, metadata: {mimeType: "image/png"}};
    string description = check provider->generate(`Describe the following image. ${img}.`);
    test:assertEquals(description, "This is a sample image description.");
}

@test:Config
function testGenerateWithMultimodalArray() returns ai:Error? {
    ai:TextDocument text = {content: "Product photo to review"};
    ai:ImageDocument image = {content: sampleBinaryData, metadata: {mimeType: "image/png"}};
    ai:Document[] docs = [text, image];
    string description = check provider->generate(`Describe the following image. ${docs}`);
    test:assertEquals(description, "This is a sample image description.");
}

@test:Config
function testGenerateWithMultipleImagesAndText() returns ai:Error? {
    ai:ImageDocument png = {content: sampleBinaryData, metadata: {mimeType: "image/png"}};
    ai:ImageDocument jpeg = {content: sampleBinaryData, metadata: {mimeType: "image/jpeg"}};
    ai:TextDocument caption = {content: "Compare these product shots"};
    ai:Document[] docs = [caption, png, jpeg];
    string description = check provider->generate(`Describe the following image collection. ${docs}`);
    test:assertEquals(description, "This is a sample image description.");
}

@test:Config
function testGenerateWithFileInMultimodalArrayFails() returns ai:Error? {
    ai:TextDocument text = {content: "Some text"};
    ai:FileDocument file = {content: "dummy-data"};
    ai:Document[] docs = [text, file];
    string|ai:Error result = provider->generate(`Analyze the following documents. ${docs}`);
    test:assertTrue(result is ai:Error, "expected an error for a file document in a multimodal array");
    test:assertTrue((<ai:Error>result).message().includes(UNSUPPORTED_DOC_ERROR));
}

@test:Config
function testGenerateWithMissingImageMimeFails() returns ai:Error? {
    ai:ImageDocument img = {content: sampleBinaryData};
    string|ai:Error description = provider->generate(`Describe the following image. ${img}.`);
    test:assertTrue(description is ai:Error, "expected an error when the image MIME type is missing");
    test:assertTrue((<ai:Error>description).message().includes("concrete image MIME type"));
}

@test:Config
function testGenerateWithImageUrlFails() returns ai:Error? {
    ai:ImageDocument img = {content: "https://example.com/image.jpg", metadata: {mimeType: "image/jpg"}};
    string|ai:Error description = provider->generate(`Describe the following image. ${img}.`);
    test:assertTrue(description is ai:Error, "expected an error for a URL image");
    test:assertTrue((<ai:Error>description).message().includes(INLINE_IMAGE_ONLY_ERROR));
}

@test:Config
function testGenerateWithUnsupportedDocument() returns ai:Error? {
    ai:FileDocument doc = {content: "dummy-data"};
    string|error result = provider->generate(`What is in this document. ${doc}.`);
    test:assertTrue(result is error, "expected an error for an unsupported document");
    test:assertTrue((<error>result).message().includes(UNSUPPORTED_DOC_ERROR));
}

// ── embeddings ───────────────────────────────────────────────────────────────

@test:Config
function testEmbed() returns ai:Error? {
    ai:TextChunk chunk = {content: "Embed this text."};
    ai:Embedding embedding = check embeddingProvider->embed(chunk);
    test:assertEquals(embedding, <float[]>[0.1, 0.2, 0.3]);
}

@test:Config
function testBatchEmbed() returns ai:Error? {
    ai:TextChunk[] chunks = [{content: "first"}, {content: "second"}];
    ai:Embedding[] embeddings = check embeddingProvider->batchEmbed(chunks);
    test:assertEquals(embeddings.length(), 2);
    test:assertEquals(embeddings[0], <float[]>[0.1, 0.2]);
}

@test:Config
function testEmbedRejectsNonTextChunk() returns ai:Error? {
    ai:ImageDocument img = {content: sampleBinaryData};
    ai:Embedding|ai:Error embedding = embeddingProvider->embed(img);
    test:assertTrue(embedding is ai:Error, "expected an error for a non-text chunk");
}

@test:Config
function testBatchEmbedRejectsNonTextChunk() returns ai:Error? {
    ai:TextChunk text = {content: "valid text"};
    ai:ImageDocument img = {content: sampleBinaryData};
    ai:Embedding[]|ai:Error embeddings = embeddingProvider->batchEmbed([text, img]);
    test:assertTrue(embeddings is ai:Error, "expected an error when a non-text chunk is in the batch");
}

@test:Config
function testEmbedRuntimeErrorIsWrapped() returns ai:Error? {
    // The mock returns a 5xx for this input; the provider should wrap it as an ai:Error.
    ai:TextChunk chunk = {content: "trigger-runtime-error"};
    ai:Embedding|ai:Error embedding = embeddingProvider->embed(chunk);
    test:assertTrue(embedding is ai:Error, "expected an error when the embedding call fails");
    test:assertTrue((<ai:Error>embedding).message().includes("Unable to obtain embedding"));
}
