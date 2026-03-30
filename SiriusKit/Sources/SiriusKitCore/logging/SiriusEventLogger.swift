//
//  SiriusEventLogger.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 3/4/26.
//

import os
import Foundation

public final class SiriusEventLogger {
    public typealias DestinationBuilder = @Sendable () -> [any SiriusEventLogDestination]
    
    private static let configurationQueue = DispatchQueue(label: "so.libsirius.SiriusKit.EventLogger.config")
    private static var destinationBuilder: DestinationBuilder = SiriusEventLogger.defaultDestinations

    private let category: String
    private let context: SharedState<Context>
    private let destinations: [any SiriusEventLogDestination]

    public init(
        _ category: String,
        context: SharedState<Context>,
        destinations: [any SiriusEventLogDestination]? = nil
    ) {
        self.category = category
        self.context = context
        self.destinations = destinations ?? SiriusEventLogger.makeDestinations()
    }
    
    public static func configure(
        destinationBuilder: DestinationBuilder? = nil
    ) {
        configurationQueue.sync {
            if let destinationBuilder {
                Self.destinationBuilder = destinationBuilder
            }
        }
    }
    
    // TODO: inlineable
    // XXX: StringBuilder-like하게 해봤는데 이게 퍼포먼스가 나은지, 아니면 퍼포먼스 신경 쓸 필요가 없이 그냥 interpolation을 쓰는 게 나은지는 모르겠음
    public func log(_ eventType: EventType, args: KeyValuePairs<String, String> = [:]) {
        // $REMOTE_ADDR $UID "$AUTH_METHOD" "$AUTH_ENTRY_IDENTIFIER" $CATEGORY $EVENT_NAME "[@ARGS]" "$AGENT"
        let context = context.checkpoint()
        var message = String()
        
        message.append(context.remoteAddr?.description ?? "-")
        message.append(" ")
        
        if let uid = context.uid {
            message.append(String(uid))
        } else {
            message.append("-")
        }
        message.append(" ")
        
        /*
        if let authMethod = context.authMethod {
            message.append("\"\(authMethod)\"")
        } else {
            message.append("-")
        }
        message.append(" ")
         */
        
        if let authEntryIdentifier = context.authEntryIdentifier {
            message.append("\"\(authEntryIdentifier)\"")
        } else {
            message.append("-")
        }
        message.append(" ")
        
        message.append(category)
        message.append(" ")
        
        message.append(eventType.rawValue)
        message.append(" ")
        
        if !args.isEmpty {
            // TODO: arg.value에 '"'나 공백이 들어가면 어떻게 하려 그래?"
            let argsString = args.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            message.append("\"\(argsString)\"")
        } else {
            message.append("-")
        }
        
        message.append(" ")
        
        if let agentName = context.agentName {
            message.append("\"\(agentName)\"")
        } else {
            message.append("-")
        }
        
        for destination in destinations {
            destination.write(message: message)
        }
    }
    
    private static func makeDestinations() -> [any SiriusEventLogDestination] {
        configurationQueue.sync { destinationBuilder() }
    }

    private static func defaultDestinations() -> [any SiriusEventLogDestination] {
#if canImport(OSLog)
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
            return [SiriusOSEventLogDestination()]
        } else {
            return []
        }
#else
        return [SiriusConsoleLogDestination()]
#endif
    }
}

public extension SiriusEventLogger {
    struct Context {
        // UNIX socket인 경우 아직 표현이 불가능함
        public var remoteAddr: SREndpoint?
        
        public var uid: uid_t?
        public var authMethod: String?
        public var authEntryIdentifier: String?
        
        public var agentName: String?
        
        public init() {
        }
    }
}


public extension SiriusEventLogger {
    struct EventType: RawRepresentable, Equatable, Sendable, Hashable {
        public var rawValue: String
        
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}


package extension SiriusEventLogger {
    protocol ContextHolder {
        func eventLoggerContext() -> SharedState<Context>
    }
}
