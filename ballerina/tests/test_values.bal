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

type Blog record {
    string title;
    string content;
};

type Review record {|
    int rating;
    string comment;
|};

const blog1 = {
    title: "Tips for Growing a Beautiful Garden",
    content: string `Spring is the perfect time to start your garden.
        Begin by preparing your soil with organic compost and ensure proper drainage.`
};

const blog2 = {
    title: "Essential Tips for Sports Performance",
    content: string `Success in sports requires dedicated preparation and training.
        Begin by establishing a proper warm-up routine and maintaining good form.`
};

final byte[] sampleBinaryData = [137, 80, 78, 71, 13, 10, 26, 10];

// Raw JSON for a `Review` record. Because `Review` is an object type, the
// structured-output path returns it directly (not wrapped in `result`).
const review = "{\"rating\": 8, \"comment\": \"Covers warm-up, form, equipment, and nutrition.\"}";

const reviewRecord = {
    rating: 8,
    comment: "Covers warm-up, form, equipment, and nutrition."
};
