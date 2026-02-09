//
//  SiriusLogVerbosity.swift
//  SiriusKit
//

/// Backward-compatible verbosity presets.
public enum SiriusLogVerbosity {
    case verbose
    case normal
    case quiet

    var minimumLevel: SiriusLogLevel {
        switch self {
        case .verbose:
            // FIXME: vverbose같은거 만들까?
            return .trace
        case .normal:
            return .info
        case .quiet:
            return .off
        }
    }
}
