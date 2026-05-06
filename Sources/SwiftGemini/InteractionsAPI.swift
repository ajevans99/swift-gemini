import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Wraps the Gemini Interactions API
/// (https://ai.google.dev/gemini-api/docs/interactions).
///
/// The Interactions API is Google's stateful, agent-friendly successor to
/// `:generateContent`. It supports `previous_interaction_id` for compaction
/// (no need to resend the full transcript), function-call tool loops, and
/// multimodal in/out — all over the same endpoint.
///
/// Currently in v1beta beta. Schemas are subject to non-backwards-compatible
/// change; we wrap a pragmatic subset focused on chat text + image
/// generation.
public struct GeminiInteractionsAPI: Sendable {
  let client: GeminiClient

  public init(client: GeminiClient) {
    self.client = client
  }

  /// `POST /{apiVersion}/interactions` — synchronous create.
  public func create(_ request: GeminiInteractionRequest) async throws -> GeminiInteraction {
    let apiVersion = await client.apiVersion
    return try await client.send(request, path: "\(apiVersion)/interactions")
  }

  /// `GET /{apiVersion}/interactions/{id}` — fetch a previous interaction.
  ///
  /// Useful for polling background interactions, or hydrating a stateful
  /// conversation.
  public func get(
    id: String,
    includeInput: Bool = false
  ) async throws -> GeminiInteraction {
    let apiVersion = await client.apiVersion
    let query = includeInput ? "?include_input=true" : ""
    return try await client.get(path: "\(apiVersion)/interactions/\(id)\(query)")
  }

  /// `POST /{apiVersion}/interactions?alt=sse` — server-sent-event stream.
  ///
  /// The returned `AsyncThrowingStream` yields decoded
  /// ``GeminiInteractionStreamEvent`` values. The stream finishes when the
  /// server closes the connection (typically after `interaction.complete`).
  public func stream(
    _ request: GeminiInteractionRequest
  ) async throws -> AsyncThrowingStream<GeminiInteractionStreamEvent, any Error> {
    let apiVersion = await client.apiVersion
    var streamingRequest = request
    streamingRequest.stream = true
    let httpRequest = try await client.makeStreamingRequest(
      streamingRequest,
      path: "\(apiVersion)/interactions?alt=sse"
    )
    return await client.streamSSE(httpRequest, decodeAs: GeminiInteractionStreamEvent.self)
  }
}

// MARK: - Request

public struct GeminiInteractionRequest: Codable, Sendable {
  public var model: String?
  public var agent: String?
  public var input: GeminiInteractionInput
  public var previousInteractionId: String?
  public var systemInstruction: String?
  public var responseModalities: [GeminiResponseModality]?
  public var tools: [GeminiInteractionTool]?
  public var toolConfig: GeminiInteractionToolConfig?
  public var generationConfig: GeminiInteractionGenerationConfig?
  public var safetySettings: [GeminiSafetySetting]?
  public var background: Bool?
  public var stream: Bool?

  public init(
    model: String? = nil,
    agent: String? = nil,
    input: GeminiInteractionInput,
    previousInteractionId: String? = nil,
    systemInstruction: String? = nil,
    responseModalities: [GeminiResponseModality]? = nil,
    tools: [GeminiInteractionTool]? = nil,
    toolConfig: GeminiInteractionToolConfig? = nil,
    generationConfig: GeminiInteractionGenerationConfig? = nil,
    safetySettings: [GeminiSafetySetting]? = nil,
    background: Bool? = nil,
    stream: Bool? = nil
  ) {
    self.model = model
    self.agent = agent
    self.input = input
    self.previousInteractionId = previousInteractionId
    self.systemInstruction = systemInstruction
    self.responseModalities = responseModalities
    self.tools = tools
    self.toolConfig = toolConfig
    self.generationConfig = generationConfig
    self.safetySettings = safetySettings
    self.background = background
    self.stream = stream
  }

  enum CodingKeys: String, CodingKey {
    case model
    case agent
    case input
    case previousInteractionId = "previous_interaction_id"
    case systemInstruction = "system_instruction"
    case responseModalities = "response_modalities"
    case tools
    case toolConfig = "tool_config"
    case generationConfig = "generation_config"
    case safetySettings = "safety_settings"
    case background
    case stream
  }
}

/// `input` accepts either a bare prompt string or an ordered list of input
/// items. We model both shapes so callers can use whichever is most natural.
public enum GeminiInteractionInput: Codable, Sendable {
  case text(String)
  case items([GeminiInteractionInputItem])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) {
      self = .text(text)
      return
    }
    let items = try container.decode([GeminiInteractionInputItem].self)
    self = .items(items)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .text(let text):
      try container.encode(text)
    case .items(let items):
      try container.encode(items)
    }
  }
}

/// A single typed input part. Only one of `text`, `image`, `audio`, `video`,
/// `document`, `function_call`, `function_result`, or `role`/`content` is set
/// at a time (matching Gemini's documented union).
public struct GeminiInteractionInputItem: Codable, Sendable {
  public var type: String?
  public var role: String?
  public var content: GeminiInteractionContent?
  public var text: String?
  public var uri: String?
  public var data: String?
  public var mimeType: String?
  public var name: String?
  public var callId: String?
  public var arguments: GeminiJSONValue?
  public var result: GeminiJSONValue?

  public init(
    type: String? = nil,
    role: String? = nil,
    content: GeminiInteractionContent? = nil,
    text: String? = nil,
    uri: String? = nil,
    data: String? = nil,
    mimeType: String? = nil,
    name: String? = nil,
    callId: String? = nil,
    arguments: GeminiJSONValue? = nil,
    result: GeminiJSONValue? = nil
  ) {
    self.type = type
    self.role = role
    self.content = content
    self.text = text
    self.uri = uri
    self.data = data
    self.mimeType = mimeType
    self.name = name
    self.callId = callId
    self.arguments = arguments
    self.result = result
  }

  enum CodingKeys: String, CodingKey {
    case type
    case role
    case content
    case text
    case uri
    case data
    case mimeType = "mime_type"
    case name
    case callId = "call_id"
    case arguments
    case result
  }

  // MARK: Convenience builders

  public static func userText(_ text: String) -> GeminiInteractionInputItem {
    .init(role: "user", content: .text(text))
  }

  public static func text(_ text: String) -> GeminiInteractionInputItem {
    .init(type: "text", text: text)
  }

  public static func inlineImage(
    base64: String,
    mimeType: String
  ) -> GeminiInteractionInputItem {
    .init(type: "image", data: base64, mimeType: mimeType)
  }

  public static func imageURI(
    _ uri: String,
    mimeType: String = "image/png"
  ) -> GeminiInteractionInputItem {
    .init(type: "image", uri: uri, mimeType: mimeType)
  }

  public static func functionResult(
    name: String,
    callId: String,
    result: GeminiJSONValue
  ) -> GeminiInteractionInputItem {
    .init(type: "function_result", name: name, callId: callId, result: result)
  }
}

/// `content` on an input item can itself be either a string or a list of
/// nested input items (when modelling multi-part user/model turns).
public enum GeminiInteractionContent: Codable, Sendable {
  case text(String)
  case items([GeminiInteractionInputItem])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let text = try? container.decode(String.self) {
      self = .text(text)
      return
    }
    let items = try container.decode([GeminiInteractionInputItem].self)
    self = .items(items)
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .text(let text):
      try container.encode(text)
    case .items(let items):
      try container.encode(items)
    }
  }
}

// MARK: - Tools

public struct GeminiInteractionTool: Codable, Sendable {
  public var type: String
  public var name: String?
  public var description: String?
  public var parameters: GeminiJSONValue?

  public init(
    type: String = "function",
    name: String? = nil,
    description: String? = nil,
    parameters: GeminiJSONValue? = nil
  ) {
    self.type = type
    self.name = name
    self.description = description
    self.parameters = parameters
  }
}

public struct GeminiInteractionToolConfig: Codable, Sendable {
  public var mode: String?

  public init(mode: String? = nil) {
    self.mode = mode
  }
}

// MARK: - Generation config

public struct GeminiInteractionGenerationConfig: Codable, Sendable {
  public var temperature: Double?
  public var topP: Double?
  public var topK: Int?
  public var maxOutputTokens: Int?
  public var imageConfig: GeminiInteractionImageConfig?

  public init(
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    maxOutputTokens: Int? = nil,
    imageConfig: GeminiInteractionImageConfig? = nil
  ) {
    self.temperature = temperature
    self.topP = topP
    self.topK = topK
    self.maxOutputTokens = maxOutputTokens
    self.imageConfig = imageConfig
  }

  enum CodingKeys: String, CodingKey {
    case temperature
    case topP
    case topK
    case maxOutputTokens
    case imageConfig = "image_config"
  }
}

public struct GeminiInteractionImageConfig: Codable, Sendable {
  public var aspectRatio: String?
  public var imageSize: String?

  public init(aspectRatio: String? = nil, imageSize: String? = nil) {
    self.aspectRatio = aspectRatio
    self.imageSize = imageSize
  }

  enum CodingKeys: String, CodingKey {
    case aspectRatio = "aspect_ratio"
    case imageSize = "image_size"
  }
}

// MARK: - Response

public struct GeminiInteraction: Codable, Sendable {
  public var id: String?
  public var status: String?
  public var model: String?
  public var role: String?
  public var serviceTier: String?
  public var object: String?
  public var created: String?
  public var updated: String?
  public var input: GeminiInteractionInput?
  public var outputs: [GeminiInteractionOutput]?
  public var usage: GeminiInteractionUsage?

  public init(
    id: String? = nil,
    status: String? = nil,
    model: String? = nil,
    role: String? = nil,
    serviceTier: String? = nil,
    object: String? = nil,
    created: String? = nil,
    updated: String? = nil,
    input: GeminiInteractionInput? = nil,
    outputs: [GeminiInteractionOutput]? = nil,
    usage: GeminiInteractionUsage? = nil
  ) {
    self.id = id
    self.status = status
    self.model = model
    self.role = role
    self.serviceTier = serviceTier
    self.object = object
    self.created = created
    self.updated = updated
    self.input = input
    self.outputs = outputs
    self.usage = usage
  }

  enum CodingKeys: String, CodingKey {
    case id
    case status
    case model
    case role
    case serviceTier = "service_tier"
    case object
    case created
    case updated
    case input
    case outputs
    case usage
  }
}

public struct GeminiInteractionOutput: Codable, Sendable {
  public var type: String?
  public var text: String?
  public var signature: String?
  public var data: String?
  public var mimeType: String?
  public var name: String?
  public var id: String?
  public var arguments: GeminiJSONValue?

  public init(
    type: String? = nil,
    text: String? = nil,
    signature: String? = nil,
    data: String? = nil,
    mimeType: String? = nil,
    name: String? = nil,
    id: String? = nil,
    arguments: GeminiJSONValue? = nil
  ) {
    self.type = type
    self.text = text
    self.signature = signature
    self.data = data
    self.mimeType = mimeType
    self.name = name
    self.id = id
    self.arguments = arguments
  }

  enum CodingKeys: String, CodingKey {
    case type
    case text
    case signature
    case data
    case mimeType = "mime_type"
    case name
    case id
    case arguments
  }
}

public struct GeminiInteractionUsage: Codable, Sendable {
  public var totalTokens: Int?
  public var totalInputTokens: Int?
  public var totalOutputTokens: Int?
  public var totalCachedTokens: Int?
  public var totalToolUseTokens: Int?
  public var totalThoughtTokens: Int?

  public init(
    totalTokens: Int? = nil,
    totalInputTokens: Int? = nil,
    totalOutputTokens: Int? = nil,
    totalCachedTokens: Int? = nil,
    totalToolUseTokens: Int? = nil,
    totalThoughtTokens: Int? = nil
  ) {
    self.totalTokens = totalTokens
    self.totalInputTokens = totalInputTokens
    self.totalOutputTokens = totalOutputTokens
    self.totalCachedTokens = totalCachedTokens
    self.totalToolUseTokens = totalToolUseTokens
    self.totalThoughtTokens = totalThoughtTokens
  }

  enum CodingKeys: String, CodingKey {
    case totalTokens = "total_tokens"
    case totalInputTokens = "total_input_tokens"
    case totalOutputTokens = "total_output_tokens"
    case totalCachedTokens = "total_cached_tokens"
    case totalToolUseTokens = "total_tool_use_tokens"
    case totalThoughtTokens = "total_thought_tokens"
  }
}

// MARK: - Stream events

/// Decoded SSE event. Each event has an `event_type` string discriminator.
/// Common event types:
///   - `interaction.start`
///   - `interaction.status_update`
///   - `interaction.complete`
///   - `content.start`
///   - `content.delta`
///   - `content.done`
public struct GeminiInteractionStreamEvent: Codable, Sendable {
  public var eventType: String?
  public var interactionId: String?
  public var interaction: GeminiInteraction?
  public var status: String?
  public var index: Int?
  public var content: GeminiInteractionStreamContent?
  public var delta: GeminiInteractionStreamDelta?
  public var usage: GeminiInteractionUsage?

  public init(
    eventType: String? = nil,
    interactionId: String? = nil,
    interaction: GeminiInteraction? = nil,
    status: String? = nil,
    index: Int? = nil,
    content: GeminiInteractionStreamContent? = nil,
    delta: GeminiInteractionStreamDelta? = nil,
    usage: GeminiInteractionUsage? = nil
  ) {
    self.eventType = eventType
    self.interactionId = interactionId
    self.interaction = interaction
    self.status = status
    self.index = index
    self.content = content
    self.delta = delta
    self.usage = usage
  }

  enum CodingKeys: String, CodingKey {
    case eventType = "event_type"
    case interactionId = "interaction_id"
    case interaction
    case status
    case index
    case content
    case delta
    case usage
  }
}

public struct GeminiInteractionStreamContent: Codable, Sendable {
  public var type: String?
  public var name: String?
  public var id: String?

  public init(type: String? = nil, name: String? = nil, id: String? = nil) {
    self.type = type
    self.name = name
    self.id = id
  }
}

public struct GeminiInteractionStreamDelta: Codable, Sendable {
  public var text: String?
  public var signature: String?
  public var data: String?
  public var mimeType: String?
  public var arguments: GeminiJSONValue?

  public init(
    text: String? = nil,
    signature: String? = nil,
    data: String? = nil,
    mimeType: String? = nil,
    arguments: GeminiJSONValue? = nil
  ) {
    self.text = text
    self.signature = signature
    self.data = data
    self.mimeType = mimeType
    self.arguments = arguments
  }

  enum CodingKeys: String, CodingKey {
    case text
    case signature
    case data
    case mimeType = "mime_type"
    case arguments
  }
}

// MARK: - Convenience: collapse a finished interaction's outputs

extension GeminiInteraction {
  /// Concatenated text from every `text` output part, or nil if none.
  public var concatenatedText: String? {
    let pieces = (outputs ?? [])
      .filter { $0.type == "text" }
      .compactMap(\.text)
      .filter { !$0.isEmpty }
    return pieces.isEmpty ? nil : pieces.joined()
  }

  /// First inline-image output, or nil.
  public var firstImage: GeminiInteractionOutput? {
    (outputs ?? []).first { $0.type == "image" && ($0.data?.isEmpty == false) }
  }

  /// All function-call output parts (Gemini may emit several per turn).
  public var functionCalls: [GeminiInteractionOutput] {
    (outputs ?? []).filter { $0.type == "function_call" }
  }
}
