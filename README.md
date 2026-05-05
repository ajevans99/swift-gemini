# swift-gemini

A small, focused Swift Concurrency client for Google's Gemini REST API
(`generativelanguage.googleapis.com`). Modeled after `swift-grok` and
`swift-openai` for use in server-side Swift projects (e.g. Vapor) where the
Firebase iOS SDK is not appropriate.

Currently focuses on:

- `models.generateContent(model:request:)` — text and multimodal generation,
  including image generation via models such as
  `gemini-3.1-flash-image-preview` (Nano Banana 2) and
  `gemini-3-pro-image-preview` (Nano Banana Pro).
- Returning generated images as inline base64 data inside response
  candidates (`GeminiGenerateContentResponse.firstInlineImage`).

## Usage

```swift
import SwiftGemini

let gemini = GeminiClient(apiKey: ProcessInfo.processInfo.environment["GEMINI_API_KEY"]!)

let request = GeminiGenerateContentRequest(
  contents: [.user(text: "A retro raygun duel on a rooftop, comic book art")],
  generationConfig: GeminiGenerationConfig(responseModalities: [.image, .text])
)
let response = try await gemini.models.generateContent(
  model: "gemini-3.1-flash-image-preview",
  request: request
)

if let image = response.firstInlineImage {
  // image.mimeType == "image/png"
  // image.data is base64-encoded PNG
}
```

## License

MIT.
