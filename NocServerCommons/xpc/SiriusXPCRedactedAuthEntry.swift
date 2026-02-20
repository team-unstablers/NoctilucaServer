//
//  SiriusXPCRedactedAuthEntry.swift
//  NocServerCommons
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation

/// XPC를 통해 에이전트에 전달하는 redacted AuthEntry.
/// 보안 데이터(bcrypt 해시, SSH 키 등)를 제외하고 method와 identifier만 포함한다.
@objc(SiriusXPCRedactedAuthEntry)
public final class SiriusXPCRedactedAuthEntry: NSObject, NSSecureCoding {
    public static var supportsSecureCoding: Bool { true }

    // MARK: - Properties

    /// AuthMethod.rawValue (e.g. "password", "ssh-key",
    /// "app.noctiluca.server.auth.simple-password")
    public let methodRawValue: String

    /// 엔트리 식별자
    public let identifier: String

    // MARK: - Init

    public init(methodRawValue: String, identifier: String) {
        self.methodRawValue = methodRawValue
        self.identifier = identifier
        super.init()
    }

    // MARK: - NSSecureCoding

    private enum CodingKeys {
        static let methodRawValue = "methodRawValue"
        static let identifier = "identifier"
    }

    public required init?(coder: NSCoder) {
        guard let method = coder.decodeObject(of: NSString.self, forKey: CodingKeys.methodRawValue) as? String else {
            return nil
        }

        guard let identifier = coder.decodeObject(of: NSString.self, forKey: CodingKeys.identifier) as? String else {
            return nil
        }

        self.methodRawValue = method
        self.identifier = identifier
        super.init()
    }

    public func encode(with coder: NSCoder) {
        coder.encode(methodRawValue as NSString, forKey: CodingKeys.methodRawValue)
        coder.encode(identifier as NSString, forKey: CodingKeys.identifier)
    }

    // MARK: - CustomStringConvertible

    public override var description: String {
        "SiriusXPCRedactedAuthEntry(method: \(methodRawValue), identifier: \(identifier))"
    }
}
