import Foundation

public struct GeminiModelsAPI: Sendable {
  let client: GeminiClient

  public init(client: GeminiClient) {
    self.client = client
  }

  /// POST `/{apiVersion}/models/{model}:generateContent`
  ///
  /// Used for text generation, multimodal inputs, and (for image-generation models
  /// such as `gemini-3.1-flash-image-preview` / `gemini-3-pro-image-preview`)
  /// returning generated images as inline base64 data inside the response candidates.
  public func generateContent(
    model: String,
    request: GeminiGenerateContentRequest
  ) async throws -> GeminiGenerateContentResponse {
    let apiVersion = await client.apiVersion
    return try await client.send(
      request,
      path: "\(apiVersion)/models/\(model):generateContent"
    )
  }
}

// MARK: - Request types

public struct GeminiGenerateContentRequest: Codable, Sendable {
  public var contents: [GeminiContent]
  public var systemInstruction: GeminiContent?
  public var generationConfig: GeminiGenerationConfig?
  public var safetySettings: [GeminiSafetySetting]?

  public init(
    contents: [GeminiContent],
    systemInstruction: GeminiContent? = nil,
    generationConfig: GeminiGenerationConfig? = nil,
    safetySettings: [GeminiSafetySetting]? = nil
  ) {
    self.contents = contents
    self.systemInstruction = systemInstruction
    self.generationConfig = generationConfig
    self.safetySettings = safetySettings
  }
}

public struct GeminiContent: Codable, Sendable {
  public var role: String?
  public var parts: [GeminiPart]

  public init(role: String? = nil, parts: [GeminiPart]) {
    self.role = role
    self.parts = parts
  }

  /// Convenience: a single user content with text + optional inline images.
  public static func user(text: String, inlineImages: [GeminiInlineData] = []) -> GeminiContent {
    var parts: [GeminiPart] = [.init(text: text)]
    parts.append(contentsOf: inlineImages.map { GeminiPart(inlineData: $0) })
    return GeminiContent(role: "user", parts: parts)
  }
}

public struct GeminiPart: Codable, Sendable {
  public var text: String?
  public var inlineData: GeminiInlineData?
  public var fileData: GeminiFileData?

  public init(
    text: String? = nil,
    inlineData: GeminiInlineData? = nil,
    fileData: GeminiFileData? = nil
  ) {
    self.text = text
    self.inlineData = inlineData
    self.fileData = fileData
  }

  enum CodingKeys: String, CodingKey {
    case text
    case inlineData = "inline_data"
    case fileData = "file_data"
  }
}

public struct GeminiInlineData: Codable, Sendable {
  public var mimeType: String
  public var data: String

  public init(mimeType: String, data: String) {
    self.mimeType = mimeType
    self.data = data
  }

  enum CodingKeys: String, CodingKey {
    case mimeType = "mime_type"
    case data
  }
}

public struct GeminiFileData: Codable, Sendable {
  public var mimeType: String
  public var fileUri: String

  public init(mimeType: String, fileUri: String) {
    self.mimeType = mimeType
    self.fileUri = fileUri
  }

  enum CodingKeys: String, CodingKey {
    case mimeType = "mime_type"
    case fileUri = "file_uri"
  }
}

public struct GeminiGenerationConfig: Codable, Sendable {
  public var temperature: Double?
  public var topP: Double?
  public var topK: Int?
  public var maxOutputTokens: Int?
  public var candidateCount: Int?
  public var responseMimeType: String?

  /// For image-generation models, set this to `["IMAGE", "TEXT"]` to receive
  /// generated images as inline data inside the response candidates.
  public var responseModalities: [GeminiResponseModality]?

  public init(
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    maxOutputTokens: Int? = nil,
    candidateCount: Int? = nil,
    responseMimeType: String? = nil,
    responseModalities: [GeminiResponseModality]? = nil
  ) {
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.maxOutputTokens = maxOutputTokens
    self.candidateCount = candidateCount
    self.responseMimeType = responseMimeType
    self.responseModalities = responseModalities
  }

  enum CodingKeys: String, CodingKey {
    case temperature
    case topP
    case topK
    case maxOutputTokens
    case candidateCount
    case responseMimeType
    case responseModalities
  }
}

public enum GeminiResponseModality: String, Codable, Sendable {
  case text = "TEXT"
  case image = "IMAGE"
  case audio = "AUDIO"
}

public struct GeminiSafetySetting: Codable, Sendable {
  public var category: String
  public var threshold: String

  public init(category: String, threshold: String) {
    self.category = category
    self.threshold = threshold
  }
}

// MARK: - Response types

public struct GeminiGenerateContentResponse: Codable, Sendable {
  public var candidates: [GeminiCandidate]?
  public var promptFeedback: GeminiPromptFeedback?
  public var usageMetadata: GeminiUsageMetadata?
  public var modelVersion: String?

  public init(
    candidates: [GeminiCandidate]? = nil,
    promptFeedback: GeminiPromptFeedback? = nil,
    usageMetadata: GeminiUsageMetadata? = nil,
    modelVersion: String? = nil
  ) {
    self.candidates = candidates
    self.promptFeedback = promptFeedback
    self.usageMetadata = usageMetadata
    self.modelVersion = modelVersion
  }
}

public struct GeminiCandidate: Codable, Sendable {
  public var content: GeminiContent?
  public var finishReason: String?
  public var index: Int?
  public var safetyRatings: [GeminiSafetyRating]?

  public init(
    content: GeminiContent? = nil,
    finishReason: String? = nil,
    index: Int? = nil,
    safetyRatings: [GeminiSafetyRating]? = nil
  ) {
    self.content = content
    self.finishReason = finishReason
    self.index = index
    self.safetyRatings = safetyRatings
  }
}

public struct GeminiPromptFeedback: Codable, Sendable {
  public var blockReason: String?
  public var safetyRatings: [GeminiSafetyRating]?
}

public struct GeminiSafetyRating: Codable, Sendable {
  public var category: String?
  public var probability: String?
  public var blocked: Bool?
}

public struct GeminiUsageMetadata: Codable, Sendable {
  public var promptTokenCount: Int?
  public var candidatesTokenCount: Int?
  public var totalTokenCount: Int?
}

// MARK: - Convenience helpers

extension GeminiGenerateContentResponse {
  /// Returns the first inline-image payload (base64 data + mime type) found in any
  /// candidate, or nil if the response did not include an image.
  public var firstInlineImage: GeminiInlineData? {
    for candidate in candidates ?? [] {
      for part in candidate.content?.parts ?? [] {
        if let inline = part.inlineData {
          return inline
        }
      }
    }
    return nil
  }

  /// Returns concatenated text from all parts of all candidates, or nil if no text
  /// was present.
  public var concatenatedText: String? {
    var pieces: [String] = []
    for candidate in candidates ?? [] {
      for part in candidate.content?.parts ?? [] {
        if let text = part.text, !text.isEmpty {
          pieces.append(text)
        }
      }
    }
    return pieces.isEmpty ? nil : pieces.joined()
  }
}
