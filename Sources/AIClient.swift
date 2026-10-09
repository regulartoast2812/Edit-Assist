import Foundation

struct AISettings {
    var provider: String
    var model: String
}

enum AIClient {
    static var schema: [String: Any] {
        let number: [String: Any] = ["type": "number"]
        let string: [String: Any] = ["type": "string"]
        return ["type": "object", "additionalProperties": false,
                "required": ["message", "styleUpdate", "routineUpdate", "instructionUpdate", "clearStyleReference", "scriptUpdate", "action", "confidence", "evidence"],
                "properties": [
                    "scriptUpdate": ["type": ["string", "null"]], "message": string, "styleUpdate": ["type": ["string", "null"]],
                    "routineUpdate": ["type": ["string", "null"]], "confidence": number, "evidence": string,
                    "instructionUpdate": ["type": ["string", "null"]], "clearStyleReference": ["type": "boolean"],
                    "action": ["type": "object", "additionalProperties": false,
                               "required": ["kind", "x", "y", "endX", "endY", "keys", "scroll", "purpose", "phrase"],
                               "properties": ["kind": ["type": "string", "enum": ActionPolicy.kinds],
                                              "x": number, "y": number, "endX": number, "endY": number,
                                              "keys": ["type": "array", "items": string],
                                              "scroll": ["type": "integer"], "purpose": string, "phrase": string]]]]
    }

    static func decide(settings: AISettings, context: String, screenshot: Data?, previous: Data?, style: Data?, attachments: [Data] = []) async throws -> Decision {
        try await CLIClient.decide(settings: settings, context: context, screenshot: screenshot, previous: previous, style: style, attachments: attachments)
    }
}
