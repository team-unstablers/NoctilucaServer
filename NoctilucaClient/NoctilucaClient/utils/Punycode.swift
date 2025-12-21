//
//  Punycode.swift
//  NoctilucaServer
//
//  Created by Codex on 12/21/25.
//

import Foundation

public struct Punycode {
    public init() {}

    public func isPunycode(_ hostname: String) -> Bool {
        return splitLabels(hostname).contains { $0.hasPunycodePrefix }
    }

    public func encode(_ hostname: String) -> String {
        guard hostname.isEmpty == false else { return hostname }

        let labels = splitLabels(hostname)
        var encodedLabels: [String] = []
        encodedLabels.reserveCapacity(labels.count)

        for label in labels {
            if label.isEmpty {
                encodedLabels.append(label)
                continue
            }

            if label.isASCII {
                if label.hasPunycodePrefix {
                    encodedLabels.append(label.lowercased())
                } else {
                    encodedLabels.append(label)
                }
                continue
            }

            guard let punyLabel = Self.encodeLabel(label) else {
                return hostname
            }
            encodedLabels.append(Self.punycodePrefix + punyLabel.lowercased())
        }

        return encodedLabels.joined(separator: ".")
    }

    public func decode(_ hostname: String) -> String {
        guard hostname.isEmpty == false else { return hostname }

        let labels = splitLabels(hostname)
        var decodedLabels: [String] = []
        decodedLabels.reserveCapacity(labels.count)

        for label in labels {
            if label.isEmpty {
                decodedLabels.append(label)
                continue
            }

            if label.hasPunycodePrefix {
                let startIndex = label.index(label.startIndex, offsetBy: Self.punycodePrefix.count)
                let payload = String(label[startIndex...])
                guard let decodedLabel = Self.decodeLabel(payload) else {
                    return hostname
                }
                decodedLabels.append(decodedLabel)
            } else {
                decodedLabels.append(label)
            }
        }

        return decodedLabels.joined(separator: ".")
    }
}

private extension Punycode {
    static let punycodePrefix = "xn--"
    static let base = 36
    static let tmin = 1
    static let tmax = 26
    static let skew = 38
    static let damp = 700
    static let initialBias = 72
    static let initialN = 128
    static let delimiter: UnicodeScalar = "-"

    static func splitLabels(_ hostname: String) -> [String] {
        return hostname.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }

    static func encodeLabel(_ label: String) -> String? {
        let scalars = label.unicodeScalars.map { Int($0.value) }
        let inputCount = scalars.count

        var output = String()
        output.reserveCapacity(label.count + 8)

        var b = 0
        for scalar in label.unicodeScalars {
            if scalar.value < 0x80 {
                output.unicodeScalars.append(scalar)
                b += 1
            }
        }

        var h = b
        if b > 0 {
            output.unicodeScalars.append(delimiter)
        }

        var n = initialN
        var delta = 0
        var bias = initialBias

        while h < inputCount {
            guard let m = scalars.filter({ $0 >= n }).min() else {
                return nil
            }

            guard let deltaStep = checkedMul(m - n, h + 1),
                  let newDelta = checkedAdd(delta, deltaStep) else {
                return nil
            }
            delta = newDelta
            n = m

            for value in scalars {
                if value < n {
                    guard let deltaInc = checkedAdd(delta, 1) else { return nil }
                    delta = deltaInc
                } else if value == n {
                    var q = delta
                    var k = base

                    while true {
                        let t = threshold(k, bias)
                        if q < t { break }
                        let code = t + (q - t) % (base - t)
                        output.unicodeScalars.append(encodeDigit(code))
                        q = (q - t) / (base - t)
                        k += base
                    }

                    output.unicodeScalars.append(encodeDigit(q))
                    bias = adapt(delta, h + 1, h == b)
                    delta = 0
                    h += 1
                }
            }

            guard let deltaInc = checkedAdd(delta, 1),
                  let nInc = checkedAdd(n, 1) else {
                return nil
            }
            delta = deltaInc
            n = nInc
        }

        return output
    }

    static func decodeLabel(_ label: String) -> String? {
        let scalars = Array(label.unicodeScalars)
        let inputCount = scalars.count

        var output: [Int] = []
        output.reserveCapacity(inputCount)

        var n = initialN
        var i = 0
        var bias = initialBias

        var delimiterIndex = -1
        for (index, scalar) in scalars.enumerated() {
            if scalar == delimiter {
                delimiterIndex = index
            }
        }

        if delimiterIndex >= 0 {
            for index in 0..<delimiterIndex {
                let scalar = scalars[index]
                guard scalar.value < 0x80 else { return nil }
                output.append(Int(scalar.value))
            }
        }

        var index = delimiterIndex >= 0 ? delimiterIndex + 1 : 0

        while index < inputCount {
            let oldi = i
            var w = 1
            var k = base

            while true {
                guard index < inputCount else { return nil }
                let digit = decodeDigit(scalars[index])
                guard digit >= 0 else { return nil }
                index += 1

                guard let addend = checkedMul(w, digit),
                      let newI = checkedAdd(i, addend) else {
                    return nil
                }
                i = newI

                let t = threshold(k, bias)
                if digit < t { break }

                guard let newW = checkedMul(w, base - t) else { return nil }
                w = newW
                k += base
            }

            let outCount = output.count + 1
            bias = adapt(i - oldi, outCount, oldi == 0)

            let nIncrement = i / outCount
            guard let newN = checkedAdd(n, nIncrement) else { return nil }
            n = newN
            i = i % outCount
            output.insert(n, at: i)
            i += 1
        }

        var decodedScalars = String.UnicodeScalarView()
        decodedScalars.reserveCapacity(output.count)

        for value in output {
            guard let scalar = UnicodeScalar(value) else { return nil }
            decodedScalars.append(scalar)
        }

        return String(decodedScalars)
    }

    static func threshold(_ k: Int, _ bias: Int) -> Int {
        if k <= bias { return tmin }
        if k >= bias + tmax { return tmax }
        return k - bias
    }

    static func adapt(_ delta: Int, _ numPoints: Int, _ firstTime: Bool) -> Int {
        var delta = firstTime ? delta / damp : delta / 2
        delta += delta / numPoints

        var k = 0
        let limit = ((base - tmin) * tmax) / 2
        while delta > limit {
            delta /= (base - tmin)
            k += base
        }

        return k + (((base - tmin + 1) * delta) / (delta + skew))
    }

    static func encodeDigit(_ digit: Int) -> UnicodeScalar {
        if digit < 26 {
            return UnicodeScalar(97 + digit)!
        }
        return UnicodeScalar(22 + digit)!
    }

    static func decodeDigit(_ scalar: UnicodeScalar) -> Int {
        switch scalar.value {
        case 0x30...0x39:
            return Int(scalar.value - 22)
        case 0x41...0x5A:
            return Int(scalar.value - 0x41)
        case 0x61...0x7A:
            return Int(scalar.value - 0x61)
        default:
            return -1
        }
    }

    static func checkedAdd(_ lhs: Int, _ rhs: Int) -> Int? {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : result
    }

    static func checkedMul(_ lhs: Int, _ rhs: Int) -> Int? {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? nil : result
    }
}

private extension String {
    var isASCII: Bool {
        return unicodeScalars.allSatisfy { $0.value < 0x80 }
    }

    var hasPunycodePrefix: Bool {
        guard count >= Punycode.punycodePrefix.count else { return false }
        return prefix(Punycode.punycodePrefix.count).lowercased() == Punycode.punycodePrefix
    }
}
