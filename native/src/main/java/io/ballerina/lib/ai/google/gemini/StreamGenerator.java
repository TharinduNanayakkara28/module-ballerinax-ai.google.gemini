/*
 * Copyright (c) 2026 WSO2 LLC. (http://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
package io.ballerina.lib.ai.google.gemini;

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.Module;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BTypedesc;

/**
 * Native shim for the streaming response generation of a Gemini model provider.
 *
 * <p>The {@code generateStream} method has a dependently-typed return
 * ({@code stream<td, ai:Error?>}), which the language only permits on an
 * {@code external} function. This shim trampolines to the Ballerina
 * {@code generateLlmResponseStream} helper, where the type gating and stream
 * construction logic lives.
 *
 * <p>Unlike {@link Generator}, this passes the whole model provider object rather than
 * unpacking its fields: the helper streams by calling {@code chatStream} as a remote
 * method on the provider, so it needs the object itself.
 *
 * @since 1.0.2
 */
public class StreamGenerator {
    public static Object generateStream(Environment env, BObject modelProvider,
                                        BObject prompt, BTypedesc expectedResponseTypedesc) {
        return env.getRuntime().callFunction(
                // The org and the MAJOR version here must both match Ballerina.toml exactly, or
                // the lookup fails at runtime with "Value creator object is not available for:
                // <org>/ai.google.gemini". Keep in step with `Generator`, which resolves the
                // same module for the non-streaming `generate`.
                new Module("ballerinax", "ai.google.gemini", "1"),
                "generateLlmResponseStream", null,
                modelProvider, prompt, expectedResponseTypedesc);
    }
}
