import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A Swift Concurrency client for Google's Gemini REST API
/// (https://ai.google.dev/gemini-api/docs).
///
/// Currently wraps two surfaces:
/// - The legacy `:generateContent` endpoint via ``GeminiModelsAPI`` for direct
///   text + image generation.
/// - The newer stateful Interactions API via ``GeminiInteractionsAPI``
///   (`v1beta/interactions`) which supports `previous_interaction_id`-based
///   compaction, server-sent-event streaming, function-call tool loops, and
///   multimodal input/output. The Interactions API is currently in Google's
///   beta channel and is the recommended path for chat-style usage.
///
/// The client is an `actor` so it is safe to share under Swift 6's strict
/// concurrency checks.
public actor GeminiClient {
  public struct Configuration: Sendable {
    public var baseURL: URL
    public var apiKey: String
    public var apiVersion: String
    public var userAgent: String?

    public init(
      baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!,
      apiKey: String,
      apiVersion: String = "v1beta",
      userAgent: String? = "SwiftGemini/0.1"
    ) {
      self.baseURL = baseURL
      self.apiKey = apiKey
      self.apiVersion = apiVersion
      self.userAgent = userAgent
    }
  }

  let configuration: Configuration
  let urlSession: URLSession

  /// Convenience nonisolated read of the API version, since `Configuration` is
  /// `let` and immutable after init.
  var apiVersion: String { configuration.apiVersion }

  public init(configuration: Configuration, urlSession: URLSession = .shared) {
    self.configuration = configuration
    self.urlSession = urlSession
  }

  public init(
    apiKey: String,
    baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!,
    apiVersion: String = "v1beta",
    urlSession: URLSession = .shared
  ) {
    self.configuration = .init(baseURL: baseURL, apiKey: apiKey, apiVersion: apiVersion)
    self.urlSession = urlSession
  }

  public nonisolated var models: GeminiModelsAPI { .init(client: self) }
  public nonisolated var interactions: GeminiInteractionsAPI { .init(client: self) }
}

// MARK: - Internal request plumbing

extension GeminiClient {
  func makeRequest(method: String, path: String) -> URLRequest {
    var request = URLRequest(url: configuration.baseURL.geminiAppending(path: path))
    request.httpMethod = method
    request.setValue(configuration.apiKey, forHTTPHeaderField: "x-goog-api-key")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let userAgent = configuration.userAgent {
      request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    }
    return request
  }

  func perform(_ request: URLRequest) async throws -> (HTTPURLResponse, Data) {
    let (data, response) = try await urlSession.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw GeminiTransportError.nonHTTPResponse
    }
    return (http, data)
  }

  func send<Request: Encodable, Response: Decodable>(
    _ requestBody: Request,
    method: String = "POST",
    path: String
  ) async throws -> Response {
    var request = makeRequest(method: method, path: path)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    request.httpBody = try encoder.encode(requestBody)

    let (http, data) = try await perform(request)
    try validateStatus(http.statusCode, data: data)

    let decoder = JSONDecoder()
    return try decoder.decode(Response.self, from: data)
  }

  func get<Response: Decodable>(path: String) async throws -> Response {
    let request = makeRequest(method: "GET", path: path)
    let (http, data) = try await perform(request)
    try validateStatus(http.statusCode, data: data)
    return try JSONDecoder().decode(Response.self, from: data)
  }

  func makeStreamingRequest<Request: Encodable>(
    _ requestBody: Request,
    method: String = "POST",
    path: String
  ) throws -> URLRequest {
    var request = makeRequest(method: method, path: path)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    request.httpBody = try encoder.encode(requestBody)
    return request
  }

  /// Open a server-sent-event stream and yield decoded `Event` values for each
  /// `data:` payload that successfully parses. Lines that fail to decode are
  /// skipped silently — the API occasionally interleaves comment-only lines
  /// (`:keep-alive`) and we don't want one bad event to abort the stream.
  func streamSSE<Event: Decodable & Sendable>(
    _ request: URLRequest,
    decodeAs _: Event.Type
  ) -> AsyncThrowingStream<Event, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let (bytes, response) = try await urlSession.bytes(for: request)
          guard let http = response as? HTTPURLResponse else {
            throw GeminiTransportError.nonHTTPResponse
          }
          guard (200...299).contains(http.statusCode) else {
            var collected = Data()
            for try await byte in bytes {
              collected.append(byte)
              if collected.count >= 16 * 1024 { break }
            }
            throw GeminiTransportError.httpError(
              statusCode: http.statusCode,
              body: String(data: collected, encoding: .utf8)
            )
          }

          let decoder = JSONDecoder()
          var dataBuffer = ""

          func flush() {
            guard !dataBuffer.isEmpty else { return }
            defer { dataBuffer = "" }
            // The Gemini Interactions stream terminates with the literal
            // payload `[DONE]` after the `interaction.complete` event.
            if dataBuffer == "[DONE]" { return }
            guard let payload = dataBuffer.data(using: .utf8) else { return }
            if let event = try? decoder.decode(Event.self, from: payload) {
              continuation.yield(event)
            }
          }

          for try await line in bytes.lines {
            if line.isEmpty {
              flush()
              continue
            }
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
              // The arrival of a new SSE event boundary in a stream where
              // `bytes.lines` has already stripped the blank delimiter — flush
              // any data accumulated under the previous event before starting
              // the next one.
              flush()
              continue
            }
            if line.hasPrefix("data:") {
              let value = line.dropFirst("data:".count)
                .drop(while: { $0 == " " })
              if !dataBuffer.isEmpty { dataBuffer.append("\n") }
              dataBuffer.append(String(value))
              continue
            }
            // id:, retry:, or unknown — currently ignored.
          }
          flush()
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
}

private func validateStatus(_ statusCode: Int, data: Data) throws {
  guard (200...299).contains(statusCode) else {
    let body = String(data: data, encoding: .utf8)
    throw GeminiTransportError.httpError(statusCode: statusCode, body: body)
  }
}

public enum GeminiTransportError: Error, CustomStringConvertible, Sendable {
  case nonHTTPResponse
  case httpError(statusCode: Int, body: String?)

  public var description: String {
    switch self {
    case .nonHTTPResponse:
      "Non-HTTP response"
    case .httpError(let statusCode, let body):
      "HTTP \(statusCode): \(body ?? "<empty body>")"
    }
  }
}

extension URL {
  fileprivate func geminiAppending(path: String) -> URL {
    var trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
    var query: String?
    if let questionMark = trimmed.firstIndex(of: "?") {
      query = String(trimmed[trimmed.index(after: questionMark)...])
      trimmed = String(trimmed[..<questionMark])
    }
    var url = appendingPathComponent(trimmed)
    if let query, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
      components.percentEncodedQuery = query
      if let withQuery = components.url {
        url = withQuery
      }
    }
    return url
  }
}
