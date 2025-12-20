//
//  CodecOptionsParser.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

struct CodecOptionsParser {
    private struct ParsedOptionSegment {
        let key: String
        let value: String
        let required: Bool
    }
    
    /// Parses an options string formatted as "key: 'value'; key2: 'value2'".
    static func parseAsDictionary(optionsString: String?) -> [String: String] {
        let segments = parseSegments(optionsString: optionsString)
        return segments.reduce(into: [:]) { partialResult, segment in
            partialResult[segment.key] = segment.value
        }
    }
    
    static let supportedKeys: Set<CodecOptionKey> = [
        .colorFormat,
        .hardwareAcceleration,
        .level,
        .profile
    ]
    
    /// Parses an options string into CodecOptions, splitting mandatory/optional entries with `!required`.
    static func parse(optionsString: String?) -> CodecOptions {
        let segments = parseSegments(optionsString: optionsString)
        var mandatory: [CodecOptionKey: CodecOptionValue] = [:]
        var optional: [CodecOptionKey: CodecOptionValue] = [:]
        
        for segment in segments {
            let typedKey = CodecOptionKey(rawValue: segment.key)
            guard supportedKeys.contains(typedKey) else { continue }
            
            let typedValue = CodecOptionValue(rawValue: segment.value)
            if segment.required {
                mandatory[typedKey] = typedValue
            } else {
                optional[typedKey] = typedValue
            }
        }
        
        return CodecOptions(mandatory: mandatory, optional: optional)
    }
    
    static func serialize(options: [CodecOptionKey: CodecOptionValue]) -> String {
        var segments: [String] = []
        
        for (key, value) in options {
            let segment = "\(key.rawValue): '\(value.rawValue)'"
            segments.append(segment)
        }
        
        return segments.joined(separator: "; ")
    }
    
    static func serialize(options: CodecOptions) -> String {
        let requiredSegments = options.mandatory.map { "\($0.key.rawValue): '\($0.value.rawValue)' !required" }
        let optionalSegments = options.optional.map { "\($0.key.rawValue): '\($0.value.rawValue)'" }
        return (requiredSegments + optionalSegments).joined(separator: "; ")
    }
    
    private static func parseSegments(optionsString: String?) -> [ParsedOptionSegment] {
        guard let optionsString, optionsString.isEmpty == false else { return [] }
        
        let segments = optionsString.split(separator: ";")
        var parsed: [ParsedOptionSegment] = []
        
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            var isRequired = false
            if let requiredRange = value.range(of: "!required", options: [.caseInsensitive, .backwards]) {
                // Only treat trailing "!required" (ignoring whitespace) as the pragma.
                let suffix = value[requiredRange.lowerBound...]
                if suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "!required" {
                    isRequired = true
                    value = String(value[..<requiredRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            
            // Only accept key: 'value' pattern.
            guard value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 else { continue }
            
            value.removeFirst()
            value.removeLast()
            
            parsed.append(ParsedOptionSegment(key: key, value: value, required: isRequired))
        }
        
        return parsed
    }
}
