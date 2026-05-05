import Foundation
import Testing

@testable import SwiftGemini

@Suite("GeminiGenerateContentResponse helpers")
struct GeminiGenerateContentResponseTests {
  @Test("firstInlineImage returns the first inline part across candidates")
  func firstInlineImageScansAcrossCandidates() {
    let response = GeminiGenerateContentResponse(
      candidates: [
        GeminiCandidate(
          content: GeminiContent(
            role: "model",
            parts: [
              GeminiPart(text: "Here is your image:"),
              GeminiPart(inlineData: GeminiInlineData(mimeType: "image/png", data: "QUJDRA==")),
            ]
          )
        )
      ]
    )

    #expect(response.firstInlineImage?.mimeType == "image/png")
    #expect(response.firstInlineImage?.data == "QUJDRA==")
  }

  @Test("firstInlineImage returns nil when only text parts are present")
  func firstInlineImageReturnsNilForTextOnly() {
    let response = GeminiGenerateContentResponse(
      candidates: [
        GeminiCandidate(
          content: GeminiContent(role: "model", parts: [GeminiPart(text: "no image")])
        )
      ]
    )

    #expect(response.firstInlineImage == nil)
  }

  @Test("concatenatedText joins text from every candidate part")
  func concatenatedTextJoinsParts() {
    let response = GeminiGenerateContentResponse(
      candidates: [
        GeminiCandidate(
          content: GeminiContent(
            role: "model",
            parts: [
              GeminiPart(text: "Hello, "),
              GeminiPart(text: "world!"),
            ]
          )
        )
      ]
    )

    #expect(response.concatenatedText == "Hello, world!")
  }

  @Test("user content convenience builds text + inline image parts in order")
  func userContentConvenience() {
    let content = GeminiContent.user(
      text: "describe this",
      inlineImages: [GeminiInlineData(mimeType: "image/png", data: "QUI=")]
    )

    #expect(content.role == "user")
    #expect(content.parts.count == 2)
    #expect(content.parts[0].text == "describe this")
    #expect(content.parts[1].inlineData?.data == "QUI=")
  }

  @Test("generation config encodes responseModalities for image generation")
  func generationConfigEncodesResponseModalities() throws {
    let request = GeminiGenerateContentRequest(
      contents: [.user(text: "draw a cat")],
      generationConfig: GeminiGenerationConfig(responseModalities: [.image, .text])
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(request)
    let json = String(data: data, encoding: .utf8) ?? ""

    #expect(json.contains("\"responseModalities\":[\"IMAGE\",\"TEXT\"]"))
    #expect(json.contains("\"role\":\"user\""))
    #expect(json.contains("\"text\":\"draw a cat\""))
  }
}
