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
import ballerina/ai.observe;
import ballerina/http;
import ballerina/lang.array;

type ResponseSchema record {|
    map<json> schema;
    boolean isOriginallyJsonObject = true;
|};

const JSON_CONVERSION_ERROR = "FromJsonStringError";
const CONVERSION_ERROR = "ConversionError";
const ERROR_MESSAGE = "Error occurred while attempting to parse the response from the " +
    "LLM as the expected type. Retrying and/or validating the prompt could fix the response.";
const RESULT = "result";
const NO_RELEVANT_RESPONSE_FROM_THE_LLM = "No relevant response from the LLM";
const JSON_MIME_TYPE = "application/json";

isolated function generateJsonObjectSchema(map<json> schema) returns ResponseSchema {
    string[] supportedMetaDataFields = ["$schema", "$id", "$anchor", "$comment", "title", "description"];

    if schema["type"] == "object" {
        return {schema};
    }

    map<json> updatedSchema = map from var [key, value] in schema.entries()
        where supportedMetaDataFields.indexOf(key) is int
        select [key, value];

    updatedSchema["type"] = "object";
    map<json> content = map from var [key, value] in schema.entries()
        where supportedMetaDataFields.indexOf(key) !is int
        select [key, value];

    updatedSchema["properties"] = {[RESULT]: content};
    // Mark `result` as required so Gemini must populate it rather than being free
    // to return an empty object for a non-object return type.
    updatedSchema["required"] = [RESULT];

    return {schema: updatedSchema, isOriginallyJsonObject: false};
}

isolated function parseResponseAsType(string resp,
        typedesc<anydata> expectedResponseTypedesc, boolean isOriginallyJsonObject) returns anydata|error {
    if !isOriginallyJsonObject {
        map<json> respContent = check resp.fromJsonStringWithType();
        anydata|error result = trap respContent[RESULT].fromJsonWithType(expectedResponseTypedesc);
        if result is error {
            return handleParseResponseError(result);
        }
        return result;
    }

    anydata|error result = resp.fromJsonStringWithType(expectedResponseTypedesc);
    if result is error {
        return handleParseResponseError(result);
    }
    return result;
}

isolated function getExpectedResponseSchema(typedesc<anydata> expectedResponseTypedesc) returns ResponseSchema|ai:Error {
    // The compiler plugin restricts `generate`'s expected type to a `json`-convertible
    // one today; map the (unexpected) failure to an `ai:Error` rather than panicking.
    typedesc<json>|error td = expectedResponseTypedesc.ensureType();
    if td is error {
        return error ai:Error("Unsupported response type for structured generation; " +
                "expected a type convertible to 'json'.", td);
    }
    return generateJsonObjectSchema(check generateJsonSchemaForTypedescAsJson(td));
}

# Builds the Gemini content parts for a prompt: accumulated text is emitted as
# `text` parts and image documents as `inlineData` parts.
#
# + prompt - The prompt whose interpolated strings and insertions are converted
# + return - The ordered content parts, or an `ai:Error` for unsupported documents
isolated function generateChatCreationContent(ai:Prompt prompt) returns Part[]|ai:Error {
    string[] & readonly strings = prompt.strings;
    anydata[] insertions = prompt.insertions;
    Part[] parts = [];
    string accumulatedTextContent = "";

    if strings.length() > 0 {
        accumulatedTextContent += strings[0];
    }

    foreach int i in 0 ..< insertions.length() {
        anydata insertion = insertions[i];
        string str = strings[i + 1];

        if insertion is ai:Document|ai:Chunk {
            addTextPart(accumulatedTextContent, parts);
            accumulatedTextContent = "";
            check addDocumentPart(insertion, parts);
        } else if insertion is (ai:Document|ai:Chunk)[] {
            addTextPart(accumulatedTextContent, parts);
            accumulatedTextContent = "";
            foreach ai:Document|ai:Chunk doc in insertion {
                check addDocumentPart(doc, parts);
            }
        } else {
            accumulatedTextContent += insertion.toString();
        }
        accumulatedTextContent += str;
    }

    addTextPart(accumulatedTextContent, parts);
    return parts;
}

isolated function addDocumentPart(ai:Document|ai:Chunk doc, Part[] parts) returns ai:Error? {
    if doc is ai:TextDocument|ai:TextChunk {
        addTextPart(doc.content, parts);
        return;
    } else if doc is ai:ImageDocument {
        parts.push(check buildImagePart(doc));
        return;
    }
    return error ai:Error("Only text and image documents are supported.");
}

isolated function addTextPart(string content, Part[] parts) {
    if content.length() > 0 {
        parts.push({text: content});
    }
}

# Builds a Gemini `inlineData` image part. Only inline bytes are supported;
# Gemini does not fetch arbitrary remote URLs for inline data. A concrete IANA
# image MIME type is required; Gemini rejects a wildcard like `image/*`.
#
# + doc - The image document
# + return - The image part, or an `ai:Error` when a URL is supplied or the
#            MIME type is missing
isolated function buildImagePart(ai:ImageDocument doc) returns Part|ai:Error {
    ai:Url|byte[] content = doc.content;
    if content is ai:Url {
        return error ai:Error("Only inline image data ('byte[]') is supported for Gemini; received a URL.");
    }
    string? mimeType = doc.metadata?.mimeType;
    if mimeType is () {
        return error ai:Error("A concrete image MIME type (e.g. 'image/png') is required in " +
                "'metadata.mimeType' for Gemini inline images.");
    }
    return {inlineData: {mimeType, data: check getBase64EncodedString(content)}};
}

isolated function getBase64EncodedString(byte[] content) returns string|ai:Error {
    string|error binaryContent = array:toBase64(content);
    if binaryContent is error {
        return error("Failed to convert byte array to string: " + binaryContent.message() + ", " +
                        binaryContent.detail().toBalString());
    }
    return binaryContent;
}

isolated function handleParseResponseError(error chatResponseError) returns error {
    string msg = chatResponseError.message();
    if msg.includes(JSON_CONVERSION_ERROR) || msg.includes(CONVERSION_ERROR) {
        return error(string `${ERROR_MESSAGE}`, chatResponseError);
    }
    return chatResponseError;
}

# Builds an error message for a response that carried no candidates. When the
# prompt was blocked, Gemini populates `promptFeedback.blockReason`; surfacing it
# makes a blocked prompt distinguishable from a genuinely empty response.
#
# + response - The `generateContent` response with empty/absent candidates
# + return - A message naming the block reason when present, otherwise a generic one
isolated function buildEmptyCandidatesMessage(GenerateContentResponse response) returns string {
    PromptFeedback? feedback = response.promptFeedback;
    if feedback is PromptFeedback {
        string? blockReason = feedback.blockReason;
        if blockReason is string {
            return string `Prompt blocked by the model: ${blockReason}`;
        }
    }
    return "Empty response from the model";
}

# Returns a parenthetical note naming the candidate's finish reason when
# generation stopped for a reason other than normal completion ("STOP") — e.g.
# truncation ("MAX_TOKENS") or safety filtering ("SAFETY"). Helps explain an
# otherwise cryptic empty/unparseable structured response. Returns "" otherwise.
#
# + candidate - The response candidate
# + return - `" (finishReason: <reason>)"`, or "" for normal completion
isolated function finishReasonNote(Candidate candidate) returns string {
    string? finishReason = candidate.finishReason;
    if finishReason is string && finishReason != "STOP" {
        return string ` (finishReason: ${finishReason})`;
    }
    return "";
}

# Concatenates the text parts of a response candidate.
#
# + candidate - The response candidate
# + return - The combined text, or `()` when no text is present
isolated function extractTextFromCandidate(Candidate candidate) returns string? {
    Content? content = candidate.content;
    if content is () {
        return ();
    }
    string text = "";
    foreach Part part in content.parts {
        string? partText = part.text;
        if partText is string {
            text += partText;
        }
    }
    return text.length() > 0 ? text : ();
}

# Backs the dependently-typed `generate` method (via the native `Generator` shim).
# Uses Gemini's native structured output: the expected type's JSON schema is sent
# as `generationConfig.responseSchema` with `responseMimeType` = "application/json",
# and the returned JSON text is parsed back into the expected type.
#
# + httpClient - The provider's HTTP client
# + apiKey - The Gemini API key, sent as the `x-goog-api-key` header
# + modelType - The Gemini model to invoke
# + temperature - The temperature for controlling randomness in the model's output
# + maxTokens - The upper limit for the number of tokens in the generated response
# + prompt - The prompt to send
# + expectedResponseTypedesc - The caller's expected return type
# + return - The generated value bound to the expected type, or an `ai:Error`
isolated function generateLlmResponse(http:Client httpClient, string apiKey, GEMINI_MODEL_NAMES modelType,
        decimal temperature, int maxTokens, ai:Prompt prompt,
        typedesc<json> expectedResponseTypedesc) returns anydata|ai:Error {
    observe:GenerateContentSpan span = observe:createGenerateContentSpan(modelType);
    span.addProvider("gemini");

    Part[] parts;
    ResponseSchema responseSchema;
    do {
        parts = check generateChatCreationContent(prompt);
        responseSchema = check getExpectedResponseSchema(expectedResponseTypedesc);
    } on fail ai:Error err {
        span.close(err);
        return err;
    }

    // Gemini's structured output (`responseSchema`) accepts only a subset of the
    // OpenAPI 3.0 schema — broadly type, format, description, nullable, enum, items,
    // properties, required and propertyOrdering. Keywords outside that subset
    // ($schema/$ref/$defs, title, default, const, additionalProperties, and the
    // oneOf/allOf combinators) are either rejected or ignored, so
    // `sanitizeGeminiSchema` strips them before sending. Consequences to be aware of:
    // a top-level `map<T>` return type is not supported by the schema generator at
    // all (it errors), and a `map` used as a record field loses its value constraint
    // once `additionalProperties` is stripped; `$ref`-based nested schemas are not
    // resolved (they degrade to an unconstrained object); and very large or deeply
    // nested schemas may still be rejected by the API.
    json sanitizedSchema = sanitizeGeminiSchema(responseSchema.schema);
    GenerateContentRequest request = {
        contents: [{role: GEMINI_ROLE_USER, parts}],
        generationConfig: {
            temperature,
            maxOutputTokens: maxTokens,
            responseMimeType: JSON_MIME_TYPE,
            responseSchema: sanitizedSchema is map<json> ? sanitizedSchema : responseSchema.schema
        }
    };
    span.addInputMessages(request.contents.toJson());

    map<string|string[]> headers = {[API_KEY_HEADER]: apiKey};
    string path = string `/models/${modelType}:generateContent`;
    GenerateContentResponse|error response = httpClient->post(path, request, headers);
    if response is error {
        ai:Error err = error("LLM call failed: " + response.message(), response);
        span.close(err);
        return err;
    }

    Candidate[]? candidates = response.candidates;
    if candidates is () || candidates.length() == 0 {
        ai:Error err = error(buildEmptyCandidatesMessage(response));
        span.close(err);
        return err;
    }

    UsageMetadata? usage = response.usageMetadata;
    if usage is UsageMetadata {
        int? inputTokens = usage.promptTokenCount;
        if inputTokens is int {
            span.addInputTokenCount(inputTokens);
        }
        int? outputTokens = usage.candidatesTokenCount;
        if outputTokens is int {
            span.addOutputTokenCount(outputTokens);
        }
    }

    string? generatedText = extractTextFromCandidate(candidates[0]);
    if generatedText is () {
        ai:Error err = error(NO_RELEVANT_RESPONSE_FROM_THE_LLM + finishReasonNote(candidates[0]));
        span.close(err);
        return err;
    }

    anydata|error res = parseResponseAsType(generatedText, expectedResponseTypedesc,
            responseSchema.isOriginallyJsonObject);
    if res is error {
        ai:Error err = error ai:LlmInvalidGenerationError(string `Invalid value returned from the LLM Client, expected: '${
            expectedResponseTypedesc.toBalString()}', found '${res.toBalString()}'${finishReasonNote(candidates[0])}`);
        span.close(err);
        return err;
    }

    anydata|error result = res.ensureType(expectedResponseTypedesc);
    if result is error {
        ai:Error err = error ai:LlmInvalidGenerationError(string `Invalid value returned from the LLM Client, expected: '${
            expectedResponseTypedesc.toBalString()}', found '${(typeof res).toBalString()}'`);
        span.close(err);
        return err;
    }

    span.addOutputMessages(result.toJson());
    span.addOutputType(observe:JSON);
    span.close();
    return result;
}
