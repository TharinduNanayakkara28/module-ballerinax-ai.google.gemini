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

import ballerina/ai;
import ballerina/test;

final ai:ChatCompletionFunctions streamWeatherTool = {
    name: "getWeather",
    description: "Get the weather for a city",
    parameters: {"type": "object", "properties": {"city": {"type": "string"}}}
};

// Drains a chunk stream into a list, so assertions can address the whole exchange.
function collectChunks(stream<ai:ChatCompletionChunk, ai:Error?> chunks)
        returns ai:ChatCompletionChunk[]|ai:Error {
    ai:ChatCompletionChunk[] collected = [];
    check from ai:ChatCompletionChunk chunk in chunks
        do {
            collected.push(chunk);
        };
    return collected;
}

// Concatenates the text fragments of a collected chunk list.
function joinContent(ai:ChatCompletionChunk[] chunks) returns string {
    string text = "";
    foreach ai:ChatCompletionChunk chunk in chunks {
        foreach ai:ChatCompletionChunkChoice choice in chunk.choices {
            string? content = choice.delta.content;
            if content is string {
                text += content;
            }
        }
    }
    return text;
}

@test:Config {}
function testChatStreamYieldsTextFragments() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks =
        check provider->chatStream([{role: ai:USER, content: "Stream a greeting"}]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    test:assertEquals(collected.length(), 3, "every streamed chunk should surface");
    test:assertEquals(joinContent(collected), "Hello, world!",
            "text fragments should stream through in order and unaltered");
    // The role rides on the delta, and Gemini's "model" must normalize to `assistant`.
    test:assertEquals(collected[0].choices[0].delta.role, ai:ASSISTANT,
            "Gemini's 'model' role should normalize to 'assistant'");
    test:assertEquals(collected[0].id, STREAM_RESPONSE_ID);
    test:assertEquals(collected[0].model, STREAM_MODEL_VERSION);
}

@test:Config {}
function testChatStreamReportsFinishReasonOnlyOnFinalChunk() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks =
        check provider->chatStream([{role: ai:USER, content: "Stream a greeting"}]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    test:assertEquals(collected[0].choices[0].finishReason, (),
            "a mid-stream chunk must not claim the generation has finished");
    test:assertEquals(collected[1].choices[0].finishReason, ());
    test:assertEquals(collected[2].choices[0].finishReason, ai:STOP);
}

@test:Config {}
function testChatStreamCarriesUsageOnlyOnFinalChunk() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks =
        check provider->chatStream([{role: ai:USER, content: "Stream a greeting"}]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    // Gemini repeats cumulative usage on every chunk; carrying it through unfiltered would
    // let a consumer that sums chunk usage over-count.
    test:assertEquals(collected[0].usage, (), "usage must not ride on a mid-stream chunk");
    test:assertEquals(collected[1].usage, ());
    ai:CompletionTokenUsage? usage = collected[2].usage;
    if usage is () {
        test:assertFail("the final chunk should carry usage");
    }
    test:assertEquals(usage.promptTokens, 11);
    // Reasoning tokens are billed as output but reported separately, so they must be added
    // to the candidate count rather than dropped.
    test:assertEquals(usage.completionTokens, 8, "completion tokens should include thinking");
    test:assertEquals(usage.totalTokens, 19);
}

@test:Config {}
function testChatStreamMapsToolCallTurnToToolCallsFinishReason() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks = check provider->chatStream(
            [{role: ai:USER, content: "Stream tool call please"}], [streamWeatherTool]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    ai:ChatCompletionChunkChoice finalChoice = collected[collected.length() - 1].choices[0];
    // Gemini says "STOP" even when the turn ends in a function call; passing that through
    // as `stop` would tell an agent loop the turn was a final answer.
    test:assertEquals(finalChoice.finishReason, ai:TOOL_CALLS,
            "a turn ending in a function call should report 'tool_calls', not 'stop'");

    ai:ToolCallChunk[]? toolCalls = finalChoice.delta.toolCalls;
    if toolCalls is () {
        test:assertFail("the function call should surface as a tool-call chunk");
    }
    test:assertEquals(toolCalls.length(), 1);
    test:assertEquals(toolCalls[0].index, 0);
    test:assertEquals(toolCalls[0].'function?.name, "getWeather");
    // Gemini delivers arguments complete rather than fragmented, so the whole object
    // arrives in a single fragment.
    test:assertEquals(toolCalls[0].'function?.arguments, "{\"city\":\"Colombo\"}");
}

@test:Config {}
function testChatStreamPacksThoughtSignatureOntoToolCallId() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks = check provider->chatStream(
            [{role: ai:USER, content: "Stream tool call please"}], [streamWeatherTool]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    ai:ToolCallChunk[] toolCalls =
        <ai:ToolCallChunk[]>collected[collected.length() - 1].choices[0].delta.toolCalls;
    // Gemini 3 rejects a replayed call that has lost its signature, and `ai:ToolCallChunk`
    // has nowhere else to carry one, so it rides on the id exactly as on the `chat` path.
    ToolCallId unpacked = unpackToolCallId(toolCalls[0].id);
    test:assertEquals(unpacked.id, "call-1");
    test:assertEquals(unpacked.signature, MOCK_THOUGHT_SIGNATURE,
            "the thought signature must survive the streamed round trip");
    test:assertFalse(unpacked.continuesBatch, "the first call of a turn opens the batch");
}

@test:Config {}
function testChatStreamNumbersParallelToolCallsAndMarksContinuations() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks = check provider->chatStream(
            [{role: ai:USER, content: "Stream parallel tools now"}], [streamWeatherTool]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    ai:ToolCallChunk[] toolCalls = <ai:ToolCallChunk[]>collected[0].choices[0].delta.toolCalls;
    test:assertEquals(toolCalls.length(), 2);
    // Gemini gives streamed calls no index of its own; one is assigned per call so a
    // consumer can key accumulation by it.
    test:assertEquals(toolCalls[0].index, 0);
    test:assertEquals(toolCalls[1].index, 1);
    test:assertEquals(toolCalls[1].'function?.name, "getStockPrice");

    // Gemini signs only the first call of a parallel batch; the rest belong to the same
    // turn and must be marked as continuations so the turn can be replayed intact.
    test:assertFalse(unpackToolCallId(toolCalls[0].id).continuesBatch);
    test:assertTrue(unpackToolCallId(toolCalls[1].id).continuesBatch,
            "a later call in a batch should be marked a continuation of the opening turn");
}

@test:Config {}
function testChatStreamKeepsThoughtsOutOfContent() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks =
        check provider->chatStream([{role: ai:USER, content: "Stream thoughts aloud"}]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    // A thought part is chain-of-thought, not answer text; folding it into `content` would
    // leak the model's reasoning into the reply.
    test:assertEquals(collected[0].choices[0].delta.content, (),
            "a thought part must not surface as answer content");
    test:assertEquals(collected[0].choices[0].delta.reasoning, "weighing options");
    test:assertEquals(joinContent(collected), "The answer is 42.");
}

@test:Config {}
function testChatStreamMapsTruncationToLength() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks =
        check provider->chatStream([{role: ai:USER, content: "Stream truncated output"}]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    test:assertEquals(collected[0].choices[0].finishReason, ai:LENGTH);
}

@test:Config {}
function testChatStreamMapsSafetyStopToContentFilter() returns error? {
    stream<ai:ChatCompletionChunk, ai:Error?> chunks =
        check provider->chatStream([{role: ai:USER, content: "Stream filtered output"}]);
    ai:ChatCompletionChunk[] collected = check collectChunks(chunks);

    test:assertEquals(collected[0].choices[0].finishReason, ai:CONTENT_FILTER);
}

@test:Config {}
function testChatStreamSurfacesHttpErrorStatus() {
    stream<ai:ChatCompletionChunk, ai:Error?>|ai:Error chunks =
        provider->chatStream([{role: ai:USER, content: "Stream auth error now"}]);

    // Targeting `http:Response` means the client hands back 4xx as an ordinary response, so
    // the status has to be caught here rather than surfacing as an empty event stream.
    if chunks !is ai:Error {
        test:assertFail("a 401 on the streaming endpoint should be reported as an error");
    }
    test:assertTrue(chunks.message().includes("401"), chunks.message());
    test:assertTrue(chunks.message().includes("UNAUTHENTICATED"), chunks.message());
}

@test:Config {}
function testGenerateStreamProjectsChunksToText() returns error? {
    stream<string, ai:Error?> textStream = check provider->generateStream(`Stream a greeting`);
    string answer = "";
    check from string fragment in textStream
        do {
            answer += fragment;
        };
    test:assertEquals(answer, "Hello, world!");
}

@test:Config {}
function testGenerateStreamRejectsNonStringType() {
    // A partial generation is a valid value only for `string`; a record has no meaningful
    // intermediate state, so the type must be refused rather than half-built.
    stream<int, ai:Error?>|ai:Error result = provider->generateStream(`Stream a greeting`);
    if result !is ai:Error {
        test:assertFail("'generateStream' should reject a non-string expected type");
    }
    test:assertTrue(result.message().includes("only 'string'"), result.message());
}
