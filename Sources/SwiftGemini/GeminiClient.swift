import Foundation

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// A Swift Concurrency client for Google's Gemini REST API
/// (https://ai.google.dev/gemini-api/docs).
///
/// This package focuses on wrapping the `:generateContent` endpoint used for
/// text + image generation (including the "Nano Banana" image-generation models
/// such as `gemini-3.1-flash-image-preview` and `gemini-3-pro-image-preview`).
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

  /// Convenience nonisolated read of the API version, since `Configuration` is `let`
  /// and immutable after init (used by `GeminiModelsAPI` to build URLs).
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
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
    return appendingPathComponent(trimmed)
  }
}
