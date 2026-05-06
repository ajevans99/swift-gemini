import Foundation

/// A type-erased JSON value used for arbitrary tool arguments and results in
/// the Interactions API. Mirrors the canonical JSON value space (string,
/// number, bool, null, array, object) and round-trips through `Codable`
/// without information loss.
public enum GeminiJSONValue: Codable, Sendable, Equatable {
  case string(String)
  case integer(Int64)
  case double(Double)
  case bool(Bool)
  case null
  case array([GeminiJSONValue])
  case object([String: GeminiJSONValue])

  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
      return
    }
    if let value = try? container.decode(Bool.self) {
      self = .bool(value)
      return
    }
    if let value = try? container.decode(Int64.self) {
      self = .integer(value)
      return
    }
    if let value = try? container.decode(Double.self) {
      self = .double(value)
      return
    }
    if let value = try? container.decode(String.self) {
      self = .string(value)
      return
    }
    if let value = try? container.decode([GeminiJSONValue].self) {
      self = .array(value)
      return
    }
    if let value = try? container.decode([String: GeminiJSONValue].self) {
      self = .object(value)
      return
    }
    throw DecodingError.dataCorruptedError(
      in: container,
      debugDescription: "Unsupported JSON value"
    )
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .integer(let value):
      try container.encode(value)
    case .double(let value):
      try container.encode(value)
    case .bool(let value):
      try container.encode(value)
    case .null:
      try container.encodeNil()
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }

  /// Convenience: parse a JSON string into a `GeminiJSONValue`. Returns `nil`
  /// if the input isn't valid JSON.
  public static func parse(_ jsonString: String) -> GeminiJSONValue? {
    guard let data = jsonString.data(using: .utf8) else { return nil }
    return try? JSONDecoder().decode(GeminiJSONValue.self, from: data)
  }

  /// Convenience: encode this value back to a JSON string.
  public func toJSONString() -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let data = try? encoder.encode(self) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
