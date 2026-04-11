//
//  Binding+Convert.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SwiftUI

import SiriusKit

/// https://stackoverflow.com/a/74356845
public extension Binding {
    static func convert<TInt, TFloat>(_ intBinding: Binding<TInt>) -> Binding<TFloat>
    where TInt:   BinaryInteger,
          TFloat: BinaryFloatingPoint{

        Binding<TFloat> (
            get: { TFloat(intBinding.wrappedValue) },
            set: { intBinding.wrappedValue = TInt($0) }
        )
    }

    static func convert<TFloat, TInt>(_ floatBinding: Binding<TFloat>) -> Binding<TInt>
    where TFloat: BinaryFloatingPoint,
          TInt:   BinaryInteger {

        Binding<TInt> (
            get: { TInt(floatBinding.wrappedValue) },
            set: { floatBinding.wrappedValue = TFloat($0) }
        )
    }
}

public extension Binding {
    static func convert<TFloat>(_ valueBinding: Binding<CodecOptionValue?>) -> Binding<TFloat>
    where TFloat:  BinaryFloatingPoint{
        Binding<TFloat> (
            get: { TFloat(Int(valueBinding.wrappedValue?.rawValue ?? "0")!) },
            set: { valueBinding.wrappedValue = .init(rawValue: String(Int($0))) }
        )
    }

    static func convert<TFloat>(_ floatBinding: Binding<TFloat>) -> Binding<CodecOptionValue?>
    where TFloat: BinaryFloatingPoint {

        Binding<CodecOptionValue?> (
            get: { CodecOptionValue(rawValue: String(Int(floatBinding.wrappedValue))) },
            set: { floatBinding.wrappedValue = TFloat(Int($0?.rawValue ?? "0")!) }
        )
    }
}
