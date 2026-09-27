import Foundation
import XCTest
@testable import AsistCore

/// WP13 (04 Appendix B.2 / revision 3; doc 06): request encoding per model, schema strictness, response decoding
/// (thinking / fallback / unknown blocks, refusal, max_tokens, malformed JSON), HTTP policy and the validator.
/// Reference instant: Sun 2026-09-27 10:30 (Europe/Istanbul).
final class SmartModeWireTests: XCTestCase {
    private let calendar = TestSupport.calendar
    private let now = TestSupport.date("2026-09-27T10:30")

    private func parserSettings() -> ParserSettings {
        var settings = ParserSettings()
        settings.knownProjects = ["Ford Otosan", "Ford"]
        settings.knownPlaces = ["Fabrika"]
        return settings
    }

    private func decodeJSON(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func keys(_ value: JSONValue?) -> [String] {
        let members = value?.objectValue ?? [:]
        return members.keys.sorted()
    }

    // MARK: - Response fixtures

    private func envelope(stopReason: String?, blocks: [JSONValue]) throws -> Data {
        var members: [String: JSONValue] = [
            "id": .string("msg_test"),
            "type": .string("message"),
            "role": .string("assistant"),
            "model": .string("claude-opus-5"),
            "content": .array(blocks),
            "usage": .object(["input_tokens": .integer(120), "output_tokens": .integer(60)])
        ]
        if let reason = stopReason {
            members["stop_reason"] = .string(reason)
        } else {
            members["stop_reason"] = .null
        }
        return try JSONEncoder().encode(JSONValue.object(members))
    }

    private func textBlock(_ text: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(text)])
    }

    private let thinkingBlock: JSONValue = .object([
        "type": .string("thinking"),
        "thinking": .string(""),
        "signature": .string("EqQBCkYIBxgCKkA")
    ])

    private let fallbackBlock: JSONValue = .object([
        "type": .string("fallback"),
        "from": .object(["model": .string("claude-opus-5")]),
        "to": .object(["model": .string("claude-opus-4-8")])
    ])

    /// An unknown future block whose `text` is not a string must not break decoding.
    private let unknownBlock: JSONValue = .object([
        "type": .string("server_note"),
        "text": .object(["nested": .integer(1)])
    ])

    private let sampleParseJSON = """
    {"kind":"reminder","title":"Ahmet'i ara","body":null,"due":"2026-09-28T14:00","hasTime":true,\
    "recurrence":null,"priority":"high","person":"Ahmet","project":"ford otosan","place":null,\
    "leadTimesMinutes":[30,30,-5],"command":null,"confidence":0.97}
    """

    private func response(kind: String = "task", title: String = "Teklifi gönder", due: String? = nil,
                          hasTime: Bool = false, recurrence: SmartParseResponse.RecurrenceDTO? = nil,
                          project: String? = nil, command: SmartParseResponse.CommandDTO? = nil,
                          body: String? = nil, confidence: Double = 0.8) -> SmartParseResponse {
        SmartParseResponse(kind: kind, title: title, body: body, due: due, hasTime: hasTime, recurrence: recurrence,
                           priority: "normal", person: nil, project: project, place: nil, leadTimesMinutes: [],
                           command: command, confidence: confidence)
    }

    private func validate(_ response: SmartParseResponse, text: String = "cümle") -> ParseResult? {
        SmartModeValidator.parseResult(from: response, originalText: text, now: now, calendar: calendar,
                                       parserSettings: parserSettings())
    }

    // MARK: - Models

    func testModelIDsAndCapabilities() {
        XCTAssertEqual(SmartModeModelID.all, ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"])
        XCTAssertEqual(SmartModeModelID.defaultID, "claude-opus-5")
        XCTAssertEqual(SmartModeModelID.normalized("claude-opus-5-20260401"), "claude-opus-5")
        XCTAssertEqual(SmartModeModelID.normalized(" claude-haiku-4-5 "), "claude-haiku-4-5")
        XCTAssertEqual(SmartModeModelID.normalized(""), "claude-opus-5")
        XCTAssertTrue(SmartModeModelID.supportsEffort("claude-opus-5"))
        XCTAssertTrue(SmartModeModelID.supportsEffort("claude-sonnet-5"))
        XCTAssertFalse(SmartModeModelID.supportsEffort("claude-haiku-4-5"))
        XCTAssertTrue(SmartModeModelID.usesServerFallback("claude-opus-5"))
        XCTAssertFalse(SmartModeModelID.usesServerFallback("claude-sonnet-5"))
        XCTAssertFalse(SmartModeModelID.usesServerFallback("claude-haiku-4-5"))
        XCTAssertEqual(SmartModeModelID.label("claude-opus-5"), "Claude Opus 5 (varsayılan, en akıllı)")
        XCTAssertEqual(SmartModeModelID.label("claude-sonnet-5"), "Claude Sonnet 5 (dengeli)")
        XCTAssertEqual(SmartModeModelID.label("claude-haiku-4-5"), "Claude Haiku 4.5 (en hızlı/ucuz)")
        XCTAssertEqual(SmartModeModelID.shortLabel("claude-haiku-4-5"), "Haiku 4.5")
    }

    // MARK: - Request encoding

    func testOpusParseRequestBodyAndHeaders() throws {
        let request = SmartModeRequestBuilder.request(model: "claude-opus-5", system: SmartModePrompts.parseSystem,
                                                      user: "Cümle: \"yarın 2'de Ahmet'i ara\"",
                                                      schema: SmartModeSchemas.parse, effort: "low", maxTokens: 4096)
        let json = try decodeJSON(try SmartModeRequestBuilder.body(request))
        XCTAssertEqual(json["model"]?.stringValue, "claude-opus-5")
        XCTAssertEqual(json["max_tokens"]?.intValue, 4096)
        XCTAssertEqual(json["fallbacks"]?.stringValue, "default")
        XCTAssertEqual(json["system"]?.stringValue, SmartModePrompts.parseSystem)
        let messages = json["messages"]?.arrayValue ?? []
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages.first?["role"]?.stringValue, "user")
        XCTAssertEqual(messages.first?["content"]?.stringValue, "Cümle: \"yarın 2'de Ahmet'i ara\"")
        XCTAssertEqual(json["output_config"]?["effort"]?.stringValue, "low")
        XCTAssertEqual(json["output_config"]?["format"]?["type"]?.stringValue, "json_schema")
        XCTAssertEqual(json["output_config"]?["format"]?["schema"], SmartModeSchemas.parse)
        for forbidden in ["temperature", "top_p", "top_k", "thinking", "stop_sequences"] {
            XCTAssertNil(json[forbidden], forbidden)
        }
        XCTAssertEqual(keys(json), ["fallbacks", "max_tokens", "messages", "model", "output_config", "system"])

        let headers = SmartModeRequestBuilder.headers(model: "claude-opus-5", apiKey: "test-key")
        XCTAssertEqual(headers["x-api-key"], "test-key")
        XCTAssertEqual(headers["anthropic-version"], "2023-06-01")
        XCTAssertEqual(headers["content-type"], "application/json")
        XCTAssertEqual(headers["anthropic-beta"], "server-side-fallback-2026-07-01")
        XCTAssertEqual(SmartModeRequestBuilder.endpoint, "https://api.anthropic.com/v1/messages")
    }

    func testHaikuRequestSendsNoEffortAndNoFallback() throws {
        let request = SmartModeRequestBuilder.request(model: "claude-haiku-4-5", system: "s", user: "u",
                                                      schema: SmartModeSchemas.parse, effort: "low", maxTokens: 4096)
        let json = try decodeJSON(try SmartModeRequestBuilder.body(request))
        XCTAssertEqual(json["model"]?.stringValue, "claude-haiku-4-5")
        XCTAssertNil(json["fallbacks"])
        XCTAssertNil(json["output_config"]?["effort"])
        XCTAssertEqual(json["output_config"]?["format"]?["type"]?.stringValue, "json_schema")
        XCTAssertNil(json["thinking"])
        let headers = SmartModeRequestBuilder.headers(model: "claude-haiku-4-5", apiKey: "k")
        XCTAssertNil(headers["anthropic-beta"])
    }

    func testSonnetKeepsEffortWithoutFallback() throws {
        let request = SmartModeRequestBuilder.request(model: "claude-sonnet-5", system: SmartModePrompts.summarySystem,
                                                      user: "u", schema: SmartModeSchemas.summary, effort: "medium",
                                                      maxTokens: 8000)
        let json = try decodeJSON(try SmartModeRequestBuilder.body(request))
        XCTAssertEqual(json["output_config"]?["effort"]?.stringValue, "medium")
        XCTAssertEqual(json["max_tokens"]?.intValue, 8000)
        XCTAssertNil(json["fallbacks"])
        XCTAssertNil(SmartModeRequestBuilder.headers(model: "claude-sonnet-5", apiKey: "k")["anthropic-beta"])
    }

    func testUnknownModelFallsBackToOpusWithFallbacks() throws {
        let request = SmartModeRequestBuilder.request(model: "claude-3-opus", system: "s", user: "u", schema: nil,
                                                      effort: "low", maxTokens: 256)
        XCTAssertEqual(request.model, "claude-opus-5")
        XCTAssertEqual(request.fallbacks, "default")
    }

    func testConnectionTestRequestWithoutSchemaOrEffortOmitsOutputConfig() throws {
        let request = SmartModeRequestBuilder.request(model: "claude-haiku-4-5", system: SmartModePrompts.testSystem,
                                                      user: SmartModePrompts.testUser, schema: nil, effort: "low",
                                                      maxTokens: 256)
        XCTAssertNil(request.outputConfig)
        let json = try decodeJSON(try SmartModeRequestBuilder.body(request))
        XCTAssertNil(json["output_config"])
        XCTAssertEqual(keys(json), ["max_tokens", "messages", "model", "system"])
    }

    func testBodyIsByteStable() throws {
        let first = try SmartModeRequestBuilder.body(SmartModeRequestBuilder.request(
            model: "claude-opus-5", system: SmartModePrompts.parseSystem, user: "x", schema: SmartModeSchemas.parse,
            effort: "low", maxTokens: 4096))
        let second = try SmartModeRequestBuilder.body(SmartModeRequestBuilder.request(
            model: "claude-opus-5", system: SmartModePrompts.parseSystem, user: "x", schema: SmartModeSchemas.parse,
            effort: "low", maxTokens: 4096))
        XCTAssertEqual(first, second)
        let text = String(data: first, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("\"additionalProperties\":false"))
        XCTAssertTrue(text.contains("\"type\":\"json_schema\""))
    }

    // MARK: - Schemas

    private func assertStrict(_ schema: JSONValue, path: String) {
        switch schema {
        case .object(let members):
            if members["type"]?.stringValue == "object" {
                XCTAssertEqual(members["additionalProperties"]?.boolValue, false, path)
                let properties = members["properties"]?.objectValue ?? [:]
                XCTAssertFalse(properties.isEmpty, path)
                var required: [String] = []
                for entry in members["required"]?.arrayValue ?? [] {
                    if let name = entry.stringValue {
                        required.append(name)
                    }
                }
                XCTAssertEqual(required.sorted(), properties.keys.sorted(), path)
            }
            for unsupported in ["minimum", "maximum", "minLength", "maxLength", "multipleOf", "pattern"] {
                XCTAssertNil(members[unsupported], path + "." + unsupported)
            }
            for (key, value) in members {
                assertStrict(value, path: path + "." + key)
            }
        case .array(let values):
            var index = 0
            for value in values {
                assertStrict(value, path: path + "[" + String(index) + "]")
                index += 1
            }
        default:
            break
        }
    }

    func testEverySchemaObjectIsStrict() {
        assertStrict(SmartModeSchemas.parse, path: "parse")
        assertStrict(SmartModeSchemas.draft, path: "draft")
        assertStrict(SmartModeSchemas.summary, path: "summary")
    }

    func testSchemaPropertiesMatchPayloadKeys() throws {
        let sample = SmartParseResponse(
            kind: "reminder", title: "T", body: "b", due: "2026-09-28T14:00", hasTime: true,
            recurrence: SmartParseResponse.RecurrenceDTO(freq: "weekly", interval: 1, weekdays: [1], monthDay: 1,
                                                         month: 1),
            priority: "high", person: "Ahmet", project: "Ford",
            place: SmartParseResponse.PlaceDTO(name: "Fabrika", trigger: "onArrive"), leadTimesMinutes: [30],
            command: SmartParseResponse.CommandDTO(type: "snooze", scope: "today", date: "2026-09-28", query: "q",
                                                   snoozeMinutes: 10),
            confidence: 0.9)
        let encoded = try decodeJSON(try JSONEncoder().encode(sample))
        let properties = SmartModeSchemas.parse["properties"]
        XCTAssertEqual(keys(encoded), keys(properties))
        let recurrenceSchema = properties?["recurrence"]?["anyOf"]?.arrayValue?.first
        XCTAssertEqual(keys(encoded["recurrence"]), keys(recurrenceSchema?["properties"]))
        let placeSchema = properties?["place"]?["anyOf"]?.arrayValue?.first
        XCTAssertEqual(keys(encoded["place"]), keys(placeSchema?["properties"]))
        let commandSchema = properties?["command"]?["anyOf"]?.arrayValue?.first
        XCTAssertEqual(keys(encoded["command"]), keys(commandSchema?["properties"]))

        let draft = try decodeJSON(try JSONEncoder().encode(SmartDraftResponse(message: "m")))
        XCTAssertEqual(keys(draft), keys(SmartModeSchemas.draft["properties"]))
        let summary = try decodeJSON(try JSONEncoder().encode(SmartProjectSummary(summary: "s", actionItems: ["a"])))
        XCTAssertEqual(keys(summary), keys(SmartModeSchemas.summary["properties"]))
    }

    // MARK: - Response decoding

    func testParseResponseWithThinkingFallbackAndUnknownBlocks() throws {
        let data = try envelope(stopReason: "end_turn",
                                blocks: [thinkingBlock, fallbackBlock, unknownBlock, textBlock(sampleParseJSON)])
        guard case .text(let text)? = SmartResponseReader.outcome(from: data) else {
            return XCTFail("metin bekleniyordu")
        }
        let parsed = try XCTUnwrap(SmartResponseReader.decode(SmartParseResponse.self, fromJSONText: text))
        XCTAssertEqual(parsed.kind, "reminder")
        XCTAssertNil(parsed.recurrence)
        let result = try XCTUnwrap(validate(parsed, text: "yarın 2'de Ahmet'i ara, acil"))
        XCTAssertEqual(result.kind, .reminder)
        XCTAssertNil(result.command)
        let item = try XCTUnwrap(result.item)
        XCTAssertEqual(item.kind, .reminder)
        XCTAssertEqual(item.title, "Ahmet'i ara")
        XCTAssertEqual(item.dueDate, TestSupport.date("2026-09-28T14:00"))
        XCTAssertTrue(item.hasTime)
        XCTAssertEqual(item.priority, .high)
        XCTAssertEqual(item.person, "Ahmet")
        XCTAssertEqual(item.project, "Ford Otosan")
        XCTAssertEqual(item.leadTimesMinutes, [30])
        XCTAssertEqual(result.confidence, 0.95)
        XCTAssertTrue(result.flags.isEmpty)
        XCTAssertEqual(result.originalText, "yarın 2'de Ahmet'i ara, acil")
        XCTAssertTrue(result.understood.contains("Ahmet'i ara"))
    }

    func testOnlyTextBlocksAreConcatenated() throws {
        let data = try envelope(stopReason: "end_turn",
                                blocks: [textBlock("{\"message\":"), thinkingBlock, textBlock("\"Merhaba\"}")])
        guard case .text(let text)? = SmartResponseReader.outcome(from: data) else {
            return XCTFail("metin bekleniyordu")
        }
        let draft = try XCTUnwrap(SmartResponseReader.decode(SmartDraftResponse.self, fromJSONText: text))
        XCTAssertEqual(draft.message, "Merhaba")
    }

    func testRawDraftAndSummaryResponses() throws {
        let draftRaw = #"{"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5","content":[{"type":"thinking","thinking":"","signature":"abc"},{"type":"text","text":"{\"message\":\"Merhaba Ahmet Bey, teklif konusunda son durum nedir? Teşekkürler.\"}"}],"stop_reason":"end_turn","stop_details":null,"usage":{"input_tokens":10,"output_tokens":20}}"#
        guard case .text(let draftText)? = SmartResponseReader.outcome(from: Data(draftRaw.utf8)) else {
            return XCTFail("metin bekleniyordu")
        }
        let draft = try XCTUnwrap(SmartResponseReader.decode(SmartDraftResponse.self, fromJSONText: draftText))
        XCTAssertEqual(draft.message, "Merhaba Ahmet Bey, teklif konusunda son durum nedir? Teşekkürler.")

        let summaryRaw = #"{"model":"claude-sonnet-5","content":[{"type":"text","text":"{\"summary\":\"Pano montajı bitti.\",\"actionItems\":[\"FAT tarihini netleştir\"]}"}],"stop_reason":"end_turn"}"#
        guard case .text(let summaryText)? = SmartResponseReader.outcome(from: Data(summaryRaw.utf8)) else {
            return XCTFail("metin bekleniyordu")
        }
        let summary = try XCTUnwrap(SmartResponseReader.decode(SmartProjectSummary.self, fromJSONText: summaryText))
        XCTAssertEqual(summary.summary, "Pano montajı bitti.")
        XCTAssertEqual(summary.actionItems, ["FAT tarihini netleştir"])
    }

    func testRefusalIsCheckedBeforeContent() throws {
        let data = try envelope(stopReason: "refusal", blocks: [textBlock(sampleParseJSON)])
        XCTAssertEqual(SmartResponseReader.outcome(from: data), .refusal)
    }

    func testMaxTokensIsTreatedAsTruncated() throws {
        let data = try envelope(stopReason: "max_tokens", blocks: [thinkingBlock, textBlock("{\"kind\":\"ta")])
        XCTAssertEqual(SmartResponseReader.outcome(from: data), .truncated)
    }

    func testEmptyAndMalformedResponses() throws {
        XCTAssertNil(SmartResponseReader.outcome(from: Data("not json".utf8)))
        XCTAssertNil(SmartResponseReader.outcome(from: Data("[1,2]".utf8)))
        XCTAssertEqual(SmartResponseReader.outcome(from: Data("{\"content\":\"x\"}".utf8)), .empty)
        let onlyThinking = try envelope(stopReason: "end_turn", blocks: [thinkingBlock])
        XCTAssertEqual(SmartResponseReader.outcome(from: onlyThinking), .empty)

        XCTAssertNil(SmartResponseReader.decode(SmartParseResponse.self, fromJSONText: "{\"kind\":\"task\""))
        XCTAssertNil(SmartResponseReader.decode(SmartParseResponse.self, fromJSONText: "Merhaba"))
        XCTAssertNil(SmartResponseReader.decode(SmartParseResponse.self, fromJSONText: "{\"kind\":\"task\"}"))
        let fenced = "```json\n{\"message\":\"Tamam\"}\n```"
        XCTAssertEqual(SmartResponseReader.decode(SmartDraftResponse.self, fromJSONText: fenced)?.message, "Tamam")
    }

    // MARK: - Errors and retry policy

    func testHTTPStatusPolicy() {
        XCTAssertEqual(SmartHTTPStatus.kind(200), .success)
        XCTAssertEqual(SmartHTTPStatus.kind(400), .badRequest)
        XCTAssertEqual(SmartHTTPStatus.kind(401), .invalidKey)
        XCTAssertEqual(SmartHTTPStatus.kind(403), .permissionDenied)
        XCTAssertEqual(SmartHTTPStatus.kind(404), .notFound)
        XCTAssertEqual(SmartHTTPStatus.kind(413), .tooLarge)
        XCTAssertEqual(SmartHTTPStatus.kind(429), .rateLimited)
        XCTAssertEqual(SmartHTTPStatus.kind(500), .serverError)
        XCTAssertEqual(SmartHTTPStatus.kind(529), .overloaded)
        XCTAssertEqual(SmartHTTPStatus.kind(302), .unexpected)

        XCTAssertEqual(SmartHTTPStatus.retryDelay(status: 429, retryAfter: "2"), 2)
        XCTAssertEqual(SmartHTTPStatus.retryDelay(status: 429, retryAfter: "30"), 5)
        XCTAssertEqual(SmartHTTPStatus.retryDelay(status: 429, retryAfter: nil), 1)
        XCTAssertEqual(SmartHTTPStatus.retryDelay(status: 429, retryAfter: "abc"), 1)
        XCTAssertEqual(SmartHTTPStatus.retryDelay(status: 529, retryAfter: nil), 1.5)
        XCTAssertEqual(SmartHTTPStatus.retryDelay(status: 500, retryAfter: nil), 1.5)
        for status in [400, 401, 403, 404, 413, 302] {
            XCTAssertNil(SmartHTTPStatus.retryDelay(status: status, retryAfter: "1"), String(status))
        }
    }

    func testErrorEnvelopeType() {
        let body = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        XCTAssertEqual(SmartAPIErrorEnvelope.errorType(from: Data(body.utf8)), "authentication_error")
        XCTAssertNil(SmartAPIErrorEnvelope.errorType(from: Data("<html>".utf8)))
    }

    // MARK: - Validator

    func testValidatorRejectsGarbage() {
        XCTAssertNil(validate(response(kind: "event")))
        XCTAssertNil(validate(response(title: "   ")))
        XCTAssertNil(validate(response(title: "...")))
        XCTAssertNil(validate(response(kind: "reminder", due: "2026-09-27T09:00", hasTime: true)))   // past
        XCTAssertNil(validate(response(due: "2026-09-26")))                                          // past day
        XCTAssertNil(validate(response(due: "2026-02-30")))
        XCTAssertNil(validate(response(due: "28.09.2026")))
        XCTAssertNil(validate(response(kind: "command")))                                            // no payload
    }

    func testValidatorDayOnlyDatesAndUnknownProject() throws {
        let today = try XCTUnwrap(validate(response(due: "2026-09-27", project: "Bosch")))
        let todayItem = try XCTUnwrap(today.item)
        XCTAssertEqual(todayItem.dueDate, TestSupport.date("2026-09-27T11:00"))   // 09:00 passed → +30 min, next hour
        XCTAssertFalse(todayItem.hasTime)
        XCTAssertNil(todayItem.project)
        XCTAssertTrue(today.flags.contains(.defaultTimeApplied))

        let later = try XCTUnwrap(validate(response(due: "2026-09-29T15:00", hasTime: false)))
        XCTAssertEqual(later.item?.dueDate, TestSupport.date("2026-09-29T09:00"))
        XCTAssertEqual(later.item?.hasTime, false)
    }

    func testValidatorNoteKeepsTextAndNeverSchedules() throws {
        let result = try XCTUnwrap(validate(response(kind: "note", title: "Pano ölçüsü", due: "2026-09-28T10:00",
                                                     hasTime: true),
                                            text: "not al pano ölçüsü 80x200"))
        XCTAssertEqual(result.kind, .note)
        XCTAssertNil(result.item?.dueDate)
        XCTAssertEqual(result.item?.body, "not al pano ölçüsü 80x200")
    }

    func testValidatorRecurrenceIsSanitized() throws {
        let weekly = SmartParseResponse.RecurrenceDTO(freq: "weekly", interval: 0, weekdays: nil, monthDay: 40,
                                                      month: nil)
        let result = try XCTUnwrap(validate(response(kind: "reminder", due: "2026-09-28T09:00", hasTime: true,
                                                     recurrence: weekly)))
        XCTAssertEqual(result.item?.recurrence, Recurrence(frequency: .weekly, interval: 1, weekdays: [1]))

        let bad = SmartParseResponse.RecurrenceDTO(freq: "hourly", interval: 1, weekdays: nil, monthDay: nil,
                                                   month: nil)
        let dropped = try XCTUnwrap(validate(response(kind: "reminder", due: "2026-09-28T09:00", hasTime: true,
                                                      recurrence: bad)))
        XCTAssertNil(dropped.item?.recurrence)
    }

    func testValidatorMapsCommands() throws {
        let query = SmartParseResponse.CommandDTO(type: "query", scope: "thisWeek", date: nil, query: nil,
                                                  snoozeMinutes: nil)
        let queryResult = try XCTUnwrap(validate(response(kind: "command", title: "Bu hafta", command: query)))
        XCTAssertEqual(queryResult.kind, .command)
        XCTAssertNil(queryResult.item)
        XCTAssertEqual(queryResult.command?.type, .query)
        XCTAssertEqual(queryResult.command?.scope, .thisWeek)

        let dateScope = SmartParseResponse.CommandDTO(type: "query", scope: "date", date: nil, query: nil,
                                                      snoozeMinutes: nil)
        XCTAssertEqual(try XCTUnwrap(validate(response(kind: "command", command: dateScope))).command?.scope, .all)

        let snooze = SmartParseResponse.CommandDTO(type: "snooze", scope: nil, date: "2026-09-28", query: "toplantı",
                                                   snoozeMinutes: nil)
        let snoozed = try XCTUnwrap(validate(response(kind: "command", command: snooze)))
        XCTAssertEqual(snoozed.command?.date, TestSupport.date("2026-09-28T09:00"))
        XCTAssertEqual(snoozed.command?.queryText, "toplantı")
        XCTAssertTrue(snoozed.flags.contains(.defaultTimeApplied))

        let minutes = SmartParseResponse.CommandDTO(type: "snooze", scope: nil, date: nil, query: nil,
                                                    snoozeMinutes: 30)
        let byMinutes = try XCTUnwrap(validate(response(kind: "command", command: minutes)))
        XCTAssertEqual(byMinutes.command?.snoozeMinutes, 30)
        XCTAssertEqual(byMinutes.command?.date, TestSupport.date("2026-09-27T11:00"))

        let past = SmartParseResponse.CommandDTO(type: "snooze", scope: nil, date: "2026-09-27T08:00", query: nil,
                                                 snoozeMinutes: nil)
        XCTAssertNil(validate(response(kind: "command", command: past)))
        let unknown = SmartParseResponse.CommandDTO(type: "delete", scope: nil, date: nil, query: nil,
                                                    snoozeMinutes: nil)
        XCTAssertNil(validate(response(kind: "command", command: unknown)))
    }

    func testLocalDateParsing() throws {
        let timed = try XCTUnwrap(SmartModeValidator.localDate("2026-09-28T14:05", calendar: calendar))
        XCTAssertEqual(timed.date, TestSupport.date("2026-09-28T14:05"))
        XCTAssertTrue(timed.hasClock)
        let seconds = try XCTUnwrap(SmartModeValidator.localDate(" 2026-09-28T14:05:00 ", calendar: calendar))
        XCTAssertEqual(seconds.date, TestSupport.date("2026-09-28T14:05"))
        let day = try XCTUnwrap(SmartModeValidator.localDate("2026-09-28", calendar: calendar))
        XCTAssertEqual(day.date, TestSupport.date("2026-09-28T00:00"))
        XCTAssertFalse(day.hasClock)
        for bad in ["", "2026-9-28", "2026-09-28T14:05Z", "2026-09-28T14:05+03:00", "2026-02-30", "28.09.2026",
                    "2026-09-28T24:00", "2026-09-28T", "2026-13-01"] {
            XCTAssertNil(SmartModeValidator.localDate(bad, calendar: calendar), bad)
        }
    }

    // MARK: - Prompts

    func testParseUserMessageCarriesTheVolatileData() {
        let message = SmartModePrompts.parseUserMessage(utterance: "  yarın 2'de ara ", now: now, calendar: calendar,
                                                        settings: parserSettings(), onDeviceHint: "Görev — Ara")
        XCTAssertTrue(message.contains("Şu an: 2026-09-27T10:30 (Pazar), saat dilimi "))
        XCTAssertTrue(message.contains("sabah 09:00"))
        XCTAssertTrue(message.contains("Projeler: Ford Otosan, Ford."))
        XCTAssertTrue(message.contains("Yerler: Fabrika."))
        XCTAssertTrue(message.contains("Cihaz içi yorum (emin değil): Görev — Ara"))
        XCTAssertTrue(message.hasSuffix("Cümle: \"yarın 2'de ara\""))
        XCTAssertFalse(SmartModePrompts.parseSystem.contains("2026"))

        let empty = SmartModePrompts.parseUserMessage(utterance: "x", now: now, calendar: calendar,
                                                      settings: ParserSettings(), onDeviceHint: "")
        XCTAssertTrue(empty.contains("Projeler: yok."))
        XCTAssertFalse(empty.contains("Cihaz içi yorum"))
    }

    func testDraftAndSummaryUserMessages() {
        let draft = SmartModePrompts.draftUserMessage(title: "Teklif", person: "Ahmet Bey", projectName: nil,
                                                      notes: "", waitingDays: 3, userName: "Gökhan")
        XCTAssertTrue(draft.contains("Takip konusu: Teklif"))
        XCTAssertTrue(draft.contains("Kişi / firma: Ahmet Bey"))
        XCTAssertTrue(draft.contains("Proje: yok"))
        XCTAssertTrue(draft.contains("Bekleme: 3 gündür bekleniyor."))
        XCTAssertTrue(draft.contains("Kullanıcı adı: Gökhan"))

        let summary = SmartModePrompts.summaryUserMessage(projectName: "Ford", notes: ["ikinci", "birinci"])
        XCTAssertTrue(summary.contains("Notlar (yeniden eskiye, 2 adet):"))
        XCTAssertTrue(summary.contains("1. ikinci"))
        XCTAssertTrue(summary.contains("2. birinci"))
    }
}
