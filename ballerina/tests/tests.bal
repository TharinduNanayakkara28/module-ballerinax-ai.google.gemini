// Copyright (c) 2025 WSO2 LLC. (http://www.wso2.org).
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
