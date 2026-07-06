## Overview

[Google Gemini](https://ai.google.dev/) is a family of multimodal large language models that support text generation, reasoning, function calling, and embeddings.

The `ai.google.gemini` connector plugs Gemini into the Ballerina [`ai`](https://central.ballerina.io/ballerina/ai) agent framework. It implements the framework's `ModelProvider` and `EmbeddingProvider` interfaces, so any agent built on `ballerina/ai` can use Gemini for chat, streaming, structured generation, and embeddings.

### Key features

- Connect and interact with Gemini large language models
- Native tool/function calling
- Structured output via Gemini's native JSON mode (`responseSchema`)
- Text and embedding model support (`embed` / `batchEmbed`)
- Secure communication using API-key authentication

> **Note:** Streaming responses are not supported in this release.

## Prerequisites

Before using this module, obtain the configuration required to engage the LLM.

- Create a Google account and sign in to [Google AI Studio](https://aistudio.google.com/).
- Generate an API key from [Google AI Studio](https://aistudio.google.com/app/apikey).

## Quickstart

To use the `ai.google.gemini` module in your Ballerina application, update the `.bal` file as follows:

### Step 1: Import the module

```ballerina
import ballerinax/ai.google.gemini;
```

### Step 2: Initialize the Model Provider

```ballerina
import ballerina/ai;
import ballerinax/ai.google.gemini;

final ai:ModelProvider geminiModel = check new gemini:ModelProvider("<API_KEY>", gemini:GEMINI_2_5_FLASH);
```

### Step 3: Invoke the model

```ballerina
public function main() returns error? {
    ai:ChatAssistantMessage response = check geminiModel->chat(
        [{role: ai:USER, content: "Explain Ballerina in one sentence."}], []);
    io:println(response.content);
}
```

### Using the Embedding Provider

```ballerina
import ballerina/ai;
import ballerinax/ai.google.gemini;

final ai:EmbeddingProvider embeddingModel =
    check new gemini:EmbeddingProvider("<API_KEY>", gemini:GEMINI_EMBEDDING_001);

public function main() returns error? {
    ai:Embedding embedding = check embeddingModel->embed({content: "Ballerina is a cloud-native language."});
}
```

## Authentication

Requests are authenticated with the Gemini API key, sent automatically as the `x-goog-api-key` header. Pass the key when constructing the provider.
