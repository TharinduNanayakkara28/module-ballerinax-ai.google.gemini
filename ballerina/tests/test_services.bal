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

import ballerina/http;

// Mock Gemini API. The connector posts to `${serviceUrl}/models/{model}:{action}`,
// so a single resource captures `models/<model>:<action>` as one path segment and
// dispatches on the action suffix.
service /llm on new http:Listener(8080) {
    resource function post models/[string operation](@http:Payload json payload)
            returns json|error {
        if operation.endsWith(":embedContent") {
            return {embedding: {values: [0.1, 0.2, 0.3]}};
        }
        if operation.endsWith(":batchEmbedContents") {
            return {embeddings: [{values: [0.1, 0.2]}, {values: [0.3, 0.4]}]};
        }
        // :generateContent — pick a response based on the first text part.
        string promptText = extractFirstText(payload);
        if promptText.startsWith("What's the weather") {
            return buildToolCallResponse("getWeather", {city: "Colombo"});
        }
        return buildTextResponse(getMockResultText(promptText));
    }
}

// Returns the first text part of `contents[0]`, or "" when absent.
isolated function extractFirstText(json payload) returns string {
    map<json> obj = payload is map<json> ? payload : {};
    json contents = obj["contents"];
    if contents is json[] && contents.length() > 0 {
        json first = contents[0];
        map<json> firstObj = first is map<json> ? first : {};
        json parts = firstObj["parts"];
        if parts is json[] {
            foreach json part in parts {
                map<json> partObj = part is map<json> ? part : {};
                json text = partObj["text"];
                if text is string {
                    return text;
                }
            }
        }
    }
    return "";
}

// Maps a prompt prefix to the text a Gemini model would return. For structured
// `generate` calls this is JSON (wrapped in `result` for non-object types); for
// plain chat it is free text.
isolated function getMockResultText(string message) returns string {
    if message.startsWith("Say hello") {
        return "Hello there!";
    }
    if message.startsWith("Evaluate") {
        return "{\"result\": [9, 1]}";
    }
    if message.startsWith("Rate this blog") {
        return "{\"result\": 4}";
    }
    if message.startsWith("Please rate this blog") {
        return review;
    }
    if message.startsWith("How would you rate this") {
        return "{\"result\": 4}";
    }
    if message.startsWith("Describe the following image") {
        return "{\"result\": \"This is a sample image description.\"}";
    }
    if message.startsWith("Give me a random joke") {
        return "{\"result\": \"Why did the chicken cross the road?\"}";
    }
    return "{\"result\": null}";
}

isolated function buildTextResponse(string text) returns json => {
    candidates: [
        {
            content: {role: "model", parts: [{text}]},
            finishReason: "STOP",
            index: 0
        }
    ],
    usageMetadata: {promptTokenCount: 10, candidatesTokenCount: 5, totalTokenCount: 15},
    modelVersion: "gemini-2.5-flash"
};

isolated function buildToolCallResponse(string name, map<json> args) returns json => {
    candidates: [
        {
            content: {role: "model", parts: [{functionCall: {name, args}}]},
            finishReason: "STOP",
            index: 0
        }
    ],
    usageMetadata: {promptTokenCount: 12, candidatesTokenCount: 6, totalTokenCount: 18},
    modelVersion: "gemini-2.5-flash"
};
