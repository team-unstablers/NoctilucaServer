//
//  PKCS8Parser.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/5/26.
//

import Foundation
import CryptoKit
import _CryptoExtras

internal import SwiftASN1

enum PKCS8ParseError: Error {
    case unsupportedAlgorithm
    case invalidFormat
    case parsingFailed
}

enum PKCS8Parser {
    private static let rsaEncryptionOID = ASN1ObjectIdentifier.AlgorithmIdentifier.rsaEncryption
    private static let ecPublicKeyOID = ASN1ObjectIdentifier.AlgorithmIdentifier.idEcPublicKey
    private static let prime256v1OID = ASN1ObjectIdentifier.NamedCurves.secp256r1

    static func parse(_ derData: Data) throws -> IdentityPrivateKey {
        do {
            let root = try DER.parse(Array(derData))
            return try parseRoot(root)
        } catch let error as PKCS8ParseError {
            throw error
        } catch is ASN1Error {
            throw PKCS8ParseError.invalidFormat
        } catch {
            throw PKCS8ParseError.parsingFailed
        }
    }

    private static func parseRoot(_ node: ASN1Node) throws -> IdentityPrivateKey {
        try DER.sequence(node, identifier: .sequence) { nodes in
            _ = try Int(derEncoded: &nodes)
            let algorithmNode = try nextNode(from: &nodes)
            let (algorithmOID, parameterOID) = try parseAlgorithmIdentifier(algorithmNode)
            let keyNode = try nextNode(from: &nodes)

            guard keyNode.identifier == .octetString,
                  case .primitive(let keyBytes) = keyNode.content
            else {
                throw PKCS8ParseError.invalidFormat
            }

            let keyData = Data(keyBytes)
            switch algorithmOID {
            case rsaEncryptionOID:
                return .rsa(try _RSA.Signing.PrivateKey(derRepresentation: keyData))
            case ecPublicKeyOID:
                guard parameterOID == prime256v1OID else {
                    throw PKCS8ParseError.unsupportedAlgorithm
                }
                return .p256(try P256.Signing.PrivateKey(derRepresentation: keyData))
            default:
                throw PKCS8ParseError.unsupportedAlgorithm
            }
        }
    }

    private static func parseAlgorithmIdentifier(_ node: ASN1Node) throws -> (ASN1ObjectIdentifier, ASN1ObjectIdentifier?) {
        try DER.sequence(node, identifier: .sequence) { nodes in
            let algorithmOID = try ASN1ObjectIdentifier(derEncoded: &nodes)
            let parameterOID = try parseAlgorithmParameter(from: &nodes)
            return (algorithmOID, parameterOID)
        }
    }

    private static func parseAlgorithmParameter(
        from nodes: inout ASN1NodeCollection.Iterator
    ) throws -> ASN1ObjectIdentifier? {
        guard let parameterNode = nodes.next() else {
            return nil
        }

        switch parameterNode.identifier {
        case .objectIdentifier:
            return try ASN1ObjectIdentifier(derEncoded: parameterNode, withIdentifier: .objectIdentifier)
        case .null:
            return nil
        default:
            throw PKCS8ParseError.invalidFormat
        }
    }

    private static func nextNode(from nodes: inout ASN1NodeCollection.Iterator) throws -> ASN1Node {
        guard let node = nodes.next() else {
            throw PKCS8ParseError.invalidFormat
        }
        return node
    }
}
