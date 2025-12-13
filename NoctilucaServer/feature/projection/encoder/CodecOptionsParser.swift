//
//  CodecOptionsParser.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

struct CodecOptionsParser {
    /// Parses an options string formatted as "key: 'value'; key2: 'value2'".
    static func parseAsDictionary(optionsString: String?) -> [String: String] {
        guard let optionsString, optionsString.isEmpty == false else { return [:] }
        
        let segments = optionsString.split(separator: ";")
        var parsed: [String: String] = [:]
        
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Only accept key: 'value' pattern.
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            } else {
                continue
            }
            
            parsed[key] = value
        }
        
        return parsed
    }
    
    static let supportedKeys: Set<CodecOptionKey> = [
        .colorFormat,
        .hardwareAcceleration,
        .level,
        .profile
    ]
    
    static func parse(optionsString: String?) -> [CodecOptionKey: CodecOptionValue] {
        let dictionary = parseAsDictionary(optionsString: optionsString)
        var options: [CodecOptionKey: CodecOptionValue] = [:]
        
        for (key, value) in dictionary {
            let typedKey   = CodecOptionKey(rawValue: key)
            let typedValue = CodecOptionValue(rawValue: value)
            
            if let typedKey, supportedKeys.contains(typedKey) {
                options[typedKey] = typedValue
            }
        }
        
        return options
    }
    
    static func serialize(options: [CodecOptionKey: CodecOptionValue]) -> String {
        var segments: [String] = []
        
        for (key, value) in options {
            let segment = "\(key.rawValue): '\(value.rawValue)'"
            segments.append(segment)
        }
        
        return segments.joined(separator: "; ")
    }
}
