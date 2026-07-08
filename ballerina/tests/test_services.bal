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

import ballerina/http;
import ballerina/test;

// Mock Gemini API. The connector posts to `${serviceUrl}/models/{model}:{action}`,
// so a single resource captures `models/<model>:<action>` as one path segment and
// dispatches on the action suffix. For `:generateContent`, the request body is
// asserted (per scenario) before a response is returned, so the request-building
// layer unique to Gemini is covered.
service /llm on new http:Listener(8080) {
    resource function post models/[string operation](@http:Payload json payload)
            returns json|error {
        if operation.endsWith(":embedContent") {
            return {embedding: {values: [0.1, 0.2, 0.3]}};
        }
        if operation.endsWith(":batchEmbedContents") {
            return {embeddings: [{values: [0.1, 0.2]}, {values: [0.3, 0.4]}]};
        }
        // :generateContent — assert the request shape, then pick a response based
        // on the first text part.
        string promptText = extractFirstText(payload);
        validateGenerateContentRequest(promptText, payload);
        if promptText.startsWith("What's the weather") {
            return buildToolCallResponse("getWeather", {city: "Colombo"});
        }
        if promptText.startsWith("Weather follow-up") {
            return buildTextResponse("It is 20 degrees in Paris.");
        }
        if promptText.startsWith("Sanitize schema") {
            return buildToolCallResponse("getWeather", {city: "Paris"});
        }
        return buildTextResponse(getMockResultText(promptText));
    }
}

// Asserts the shape of a `:generateContent` request for the scenarios that
// exercise the Gemini-specific request-building logic. No-ops for other prompts.
function validateGenerateContentRequest(string promptText, json payload) {
    map<json> obj = payload is map<json> ? payload : {};

    if promptText.startsWith("System check") {
        json systemInstruction = obj["systemInstruction"];
        test:assertTrue(systemInstruction is map<json>, "expected a systemInstruction in the request");
        test:assertEquals(firstPartText(systemInstruction), "You are a helpful assistant.");
    }

    if promptText.startsWith("Weather follow-up") {
        json contents = obj["contents"];
        test:assertTrue(contents is json[], "expected a contents array");
        json[] contentsArr = <json[]>contents;
        test:assertEquals(contentsArr.length(), 3, "expected user, model and function-response turns");

        map<json> modelTurn = <map<json>>contentsArr[1];
        test:assertEquals(modelTurn["role"], "model", "assistant turn must use the 'model' role");
        map<json> modelPart = <map<json>>(<json[]>modelTurn["parts"])[0];
        test:assertTrue(modelPart.hasKey("functionCall"), "expected a functionCall part in the model turn");
        map<json> functionCall = <map<json>>modelPart["functionCall"];
        test:assertEquals(functionCall["name"], "getWeather");

        map<json> fnTurn = <map<json>>contentsArr[2];
        test:assertEquals(fnTurn["role"], "user", "function-response turn must use the 'user' role");
        map<json> fnPart = <map<json>>(<json[]>fnTurn["parts"])[0];
        test:assertTrue(fnPart.hasKey("functionResponse"), "expected a functionResponse part");
        map<json> functionResponse = <map<json>>fnPart["functionResponse"];
        test:assertEquals(functionResponse["name"], "getWeather");
    }

    if promptText.startsWith("What's the weather using two tools") {
        json toolsJson = obj["tools"];
        test:assertTrue(toolsJson is json[] && toolsJson.length() > 0, "expected a tools array");
        map<json> firstTool = <map<json>>(<json[]>toolsJson)[0];
        json declarations = firstTool["functionDeclarations"];
        test:assertTrue(declarations is json[], "expected function declarations");
        test:assertEquals((<json[]>declarations).length(), 2, "expected two function declarations");
    }

    if promptText.startsWith("Sanitize schema") {
        map<json> params = toolParameters(obj);
        foreach string key in ["$schema", "title", "$ref", "default", "additionalProperties"] {
            test:assertFalse(params.hasKey(key), string `expected unsupported schema key '${key}' to be stripped`);
        }
        test:assertTrue(params.hasKey("properties"), "expected 'properties' to survive sanitization");
        map<json> props = params["properties"] is map<json> ? <map<json>>params["properties"] : {};
        map<json> city = props["city"] is map<json> ? <map<json>>props["city"] : {};
        test:assertFalse(city.hasKey("default"), "expected nested 'default' to be stripped");
        test:assertEquals(city["type"], "string");
    }

    if promptText.startsWith("Stop test") {
        map<json> genConfig = generationConfig(obj);
        test:assertEquals(genConfig["stopSequences"], <json[]>["END"]);
    }

    if promptText.startsWith("Config check") {
        map<json> genConfig = generationConfig(obj);
        test:assertEquals(genConfig["temperature"], 0.7d, "temperature must be forwarded to generate()");
        test:assertEquals(genConfig["maxOutputTokens"], 512, "maxTokens must be forwarded to generate()");
        test:assertEquals(genConfig["responseMimeType"], "application/json");
    }
}

// Returns the first text part of `contents[0]`, or "" when absent.
isolated function extractFirstText(json payload) returns string {
    map<json> obj = payload is map<json> ? payload : {};
    json contents = obj["contents"];
    if contents is json[] && contents.length() > 0 {
        json first = contents[0];
        return firstPartText(first) is string ? <string>firstPartText(first) : "";
    }
    return "";
}

// Returns the `text` of the first part of a content object, or `()` when absent.
isolated function firstPartText(json content) returns json {
    map<json> obj = content is map<json> ? content : {};
    json parts = obj["parts"];
    if parts is json[] {
        foreach json part in parts {
            map<json> partObj = part is map<json> ? part : {};
            json text = partObj["text"];
            if text is string {
                return text;
            }
        }
    }
    return ();
}

// Returns the request's `generationConfig` object, or `{}` when absent.
isolated function generationConfig(map<json> payload) returns map<json> {
    json genConfig = payload["generationConfig"];
    return genConfig is map<json> ? genConfig : {};
}

// Returns the parameter schema of the first function declaration of the first
// tool, or `{}` when absent.
isolated function toolParameters(map<json> payload) returns map<json> {
    json tools = payload["tools"];
    if tools is json[] && tools.length() > 0 {
        map<json> firstTool = tools[0] is map<json> ? <map<json>>tools[0] : {};
        json declarations = firstTool["functionDeclarations"];
        if declarations is json[] && declarations.length() > 0 {
            map<json> firstDeclaration = declarations[0] is map<json> ? <map<json>>declarations[0] : {};
            json params = firstDeclaration["parameters"];
            return params is map<json> ? params : {};
        }
    }
    return {};
}

// Maps a prompt prefix to the text a Gemini model would return. For structured
// `generate` calls this is JSON (wrapped in `result` for non-object types); for
// plain chat it is free text.
isolated function getMockResultText(string message) returns string {
    if message.startsWith("Say hello") {
        return "Hello there!";
    }
    if message.startsWith("System check") {
        return "System instruction received.";
    }
    if message.startsWith("Stop test") {
        return "Stopping now.";
    }
    if message.startsWith("Config check") {
        return "{\"result\": 5}";
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
