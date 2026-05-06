import Foundation
import Testing

@testable import SwiftGemini

@Suite("GeminiJSONValue")
struct GeminiJSONValueTests {
  @Test("round-trips primitive values through JSON")
  func roundTripsPrimitives() throws {
    let cases: [GeminiJSONValue] = [
      .string("hello"),
      .integer(42),
      .double(3.14),
      .bool(true),
      .null,
    ]
    for value in cases {
      let json = try #require(value.toJSONString())
      let parsed = try #require(GeminiJSONValue.parse(json))
      #expect(parsed == value)
    }
  }

  @Test("round-trips nested objects and arrays")
  func roundTripsContainers() throws {
    let value: GeminiJSONValue = .object([
      "intent": .string("retry"),
      "attempts": .integer(3),
      "tags": .array([.string("a"), .string("b")]),
      "nested": .object(["ok": .bool(true), "missing": .null]),
    ])
    let json = try #require(value.toJSONString())
    let parsed = try #require(GeminiJSONValue.parse(json))
    #expect(parsed == value)
  }

  @Test("parse returns nil for invalid JSON")
  func parseReturnsNilForInvalidJSON() {
    #expect(GeminiJSONValue.parse("{invalid") == nil)
  }
}

@Suite("GeminiInteractionsAPI shape")
struct GeminiInteractionsAPIShapeTests {
  @Test("encodes string input as a bare JSON string")
  func encodesStringInput() throws {
    let request = GeminiInteractionRequest(
      model: "gemini-3-flash-preview",
      input: .text("hi")
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(data: try encoder.encode(request), encoding: .utf8) ?? ""
    #expect(json.contains("\"input\":\"hi\""))
    #expect(json.contains("\"model\":\"gemini-3-flash-preview\""))
  }

  @Test("encodes input items as a JSON array preserving role and content")
  func encodesItemsInput() throws {
    let request = GeminiInteractionRequest(
      model: "gemini-3-flash-preview",
      input: .items([
        .userText("hello"),
        .init(role: "model", content: .text("world")),
      ])
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(data: try encoder.encode(request), encoding: .utf8) ?? ""
    #expect(json.contains("\"input\":[{"))
    #expect(json.contains("\"role\":\"user\""))
    #expect(json.contains("\"content\":\"hello\""))
    #expect(json.contains("\"role\":\"model\""))
    #expect(json.contains("\"content\":\"world\""))
  }

  @Test("encodes function_result input items with snake_case call_id")
  func encodesFunctionResultItems() throws {
    let item = GeminiInteractionInputItem.functionResult(
      name: "get_weather",
      callId: "call-1",
      result: .object(["forecast": .string("sunny")])
    )
    let json =
      String(data: try JSONEncoder().encode(item), encoding: .utf8) ?? ""
    #expect(json.contains("\"type\":\"function_result\""))
    #expect(json.contains("\"name\":\"get_weather\""))
    #expect(json.contains("\"call_id\":\"call-1\""))
    #expect(json.contains("\"forecast\":\"sunny\""))
  }

  @Test("encodes previous_interaction_id and response_modalities in snake_case")
  func encodesSnakeCasePassthroughs() throws {
    let request = GeminiInteractionRequest(
      model: "gemini-3-flash-preview",
      input: .text("hi"),
      previousInteractionId: "v1_abc",
      responseModalities: [.image, .text]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(data: try encoder.encode(request), encoding: .utf8) ?? ""
    #expect(json.contains("\"previous_interaction_id\":\"v1_abc\""))
    #expect(json.contains("\"response_modalities\":[\"IMAGE\",\"TEXT\"]"))
  }

  @Test("encodes systemInstruction as system_instruction (not 'instructions')")
  func encodesSystemInstructionSnakeCase() throws {
    // Regression test for HTTP 400 "Unknown parameter 'instructions'": the
    // Gemini Interactions API field is `system_instruction`, not the
    // OpenAI-style `instructions`.
    let request = GeminiInteractionRequest(
      model: "gemini-3-flash-preview",
      input: .text("hi"),
      systemInstruction: "You are a helpful assistant."
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(data: try encoder.encode(request), encoding: .utf8) ?? ""
    #expect(
      json.contains("\"system_instruction\":\"You are a helpful assistant.\""),
      "Expected system_instruction in encoded request, got: \(json)"
    )
    #expect(!json.contains("\"instructions\""), "Encoded request must not contain 'instructions'")
  }

  @Test("encodes thinking_config inside generation_config")
  func encodesThinkingConfig() throws {
    let request = GeminiInteractionRequest(
      model: "gemini-3-flash-preview",
      input: .text("hi"),
      generationConfig: GeminiInteractionGenerationConfig(
        thinkingConfig: GeminiThinkingConfig(level: "high", includeThoughts: true)
      )
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(data: try encoder.encode(request), encoding: .utf8) ?? ""
    #expect(json.contains("\"thinking_config\":"), "Expected thinking_config in: \(json)")
    #expect(json.contains("\"thinking_level\":\"high\""), "Expected thinking_level in: \(json)")
    #expect(json.contains("\"include_thoughts\":true"), "Expected include_thoughts in: \(json)")
    // budget is nil and should be omitted.
    #expect(!json.contains("thinking_budget"), "Did not expect thinking_budget in: \(json)")
  }

  @Test("encodes thinking_budget when set without level")
  func encodesThinkingBudget() throws {
    let config = GeminiInteractionGenerationConfig(
      thinkingConfig: GeminiThinkingConfig(budget: 1024)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = String(data: try encoder.encode(config), encoding: .utf8) ?? ""
    #expect(json.contains("\"thinking_budget\":1024"), "Expected thinking_budget in: \(json)")
    #expect(!json.contains("thinking_level"), "Did not expect thinking_level in: \(json)")
  }

  @Test("decodes a synchronous interaction response")
  func decodesInteractionResponse() throws {
    let payload = #"""
      {
        "id": "v1_abc",
        "status": "completed",
        "object": "interaction",
        "model": "gemini-3-flash-preview",
        "outputs": [
          {"type": "thought", "signature": "sig"},
          {"type": "text", "text": "Hi Phil!"},
          {"type": "function_call", "id": "call-1", "name": "get_weather", "arguments": {"location": "Paris"}}
        ],
        "usage": {
          "total_tokens": 141,
          "total_input_tokens": 8,
          "total_output_tokens": 18,
          "total_thought_tokens": 115
        }
      }
      """#
    let interaction = try JSONDecoder().decode(
      GeminiInteraction.self,
      from: payload.data(using: .utf8)!
    )
    #expect(interaction.id == "v1_abc")
    #expect(interaction.status == "completed")
    #expect(interaction.concatenatedText == "Hi Phil!")
    #expect(interaction.functionCalls.count == 1)
    #expect(interaction.functionCalls.first?.name == "get_weather")
    #expect(interaction.functionCalls.first?.arguments != nil)
    #expect(interaction.usage?.totalThoughtTokens == 115)
  }

  @Test("decodes a streaming SSE event payload")
  func decodesStreamEventPayload() throws {
    let payload = #"""
      {
        "index": 0,
        "delta": {"text": "Hello"},
        "event_type": "content.delta"
      }
      """#
    let event = try JSONDecoder().decode(
      GeminiInteractionStreamEvent.self,
      from: payload.data(using: .utf8)!
    )
    #expect(event.eventType == "content.delta")
    #expect(event.index == 0)
    #expect(event.delta?.text == "Hello")
  }

  @Test("decodes interaction.start event with embedded interaction summary")
  func decodesInteractionStartEvent() throws {
    let payload = #"""
      {
        "interaction": {
          "id": "v1_def",
          "status": "in_progress",
          "object": "interaction",
          "model": "gemini-3-flash-preview"
        },
        "event_type": "interaction.start"
      }
      """#
    let event = try JSONDecoder().decode(
      GeminiInteractionStreamEvent.self,
      from: payload.data(using: .utf8)!
    )
    #expect(event.eventType == "interaction.start")
    #expect(event.interaction?.id == "v1_def")
    #expect(event.interaction?.status == "in_progress")
  }
}
