//
//  projection_audio+Sirius.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import SwiftProtobuf

// MARK: - MessageOpcode

public extension MessageOpcode {
    static let audioProjectionRequest: MessageOpcode = MessageOpcode(rawValue: 0x80C1)
    static let stopAudioProjectionRequest: MessageOpcode = MessageOpcode(rawValue: 0x80C2)
    static let audioSessionCreatedEvent: MessageOpcode = MessageOpcode(rawValue: 0x80C3)
    static let audioSessionCreationFailedEvent: MessageOpcode = MessageOpcode(rawValue: 0x80C4)
    static let audioSessionChangedEvent: MessageOpcode = MessageOpcode(rawValue: 0x80C5)
    static let audioSessionEndedEvent: MessageOpcode = MessageOpcode(rawValue: 0x80C6)
}

// MARK: - Enums

public struct AudioSessionFailureReason: SiriusEnum {
    typealias ProtobufEnum = Sirius_Msgdef_V1_Channels_Projection_AudioSessionFailureReason

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let unknown = Self.fromProtobufEnum(.audioSessionFailureUnknown)
    public static let sourceNotFound = Self.fromProtobufEnum(.audioSessionFailureSourceNotFound)
    public static let codecNotSupported = Self.fromProtobufEnum(.audioSessionFailureCodecNotSupported)
    public static let permissionDenied = Self.fromProtobufEnum(.audioSessionFailurePermissionDenied)
}

public struct AudioSessionChangeReason: SiriusEnum {
    typealias ProtobufEnum = Sirius_Msgdef_V1_Channels_Projection_AudioSessionChangeReason

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let unknown = Self.fromProtobufEnum(.audioSessionChangeUnknown)
    public static let sourceChanged = Self.fromProtobufEnum(.audioSessionChangeSourceChanged)
    public static let codecRenegotiated = Self.fromProtobufEnum(.audioSessionChangeCodecRenegotiated)
}

public struct AudioSessionEndReason: SiriusEnum {
    typealias ProtobufEnum = Sirius_Msgdef_V1_Channels_Projection_AudioSessionEndReason

    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let unknown = Self.fromProtobufEnum(.audioSessionEndUnknown)
    public static let clientRequested = Self.fromProtobufEnum(.audioSessionEndClientRequested)
    public static let sourceUnavailable = Self.fromProtobufEnum(.audioSessionEndSourceUnavailable)
    public static let error = Self.fromProtobufEnum(.audioSessionEndError)
}

// MARK: - AudioCodec

public struct AudioCodec: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_AudioCodec

    public enum Quality {
        case constantBitrate(bitrateKbps: UInt32)
        case variableBitrate(targetBitrateKbps: UInt32, maxBitrateKbps: UInt32)
        case auto
    }

    public let fourCC: CodecFourCC
    public let quality: Quality

    /// 샘플링 레이트 (Hz). nil이면 스트림의 기본 샘플링 레이트를 사용합니다.
    public let sampleRate: UInt32?

    /// 채널 수. nil이면 스트림/코덱이 지원하는 기본 채널 수를 사용합니다.
    public let channelCount: UInt32?

    /// 추가 옵션 (예: "frame-size: 20ms; stream-type: voice;")
    public let options: CodecOptions

    public init(
        fourCC: CodecFourCC,
        quality: Quality,
        sampleRate: UInt32? = nil,
        channelCount: UInt32? = nil,
        options: CodecOptions = CodecOptions()
    ) {
        self.fourCC = fourCC
        self.quality = quality
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.options = options
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.fourCC = CodecFourCC(rawValue: protobufMessage.fourCc)

        switch protobufMessage.quality {
        case .constantBitrate(let val):
            self.quality = .constantBitrate(bitrateKbps: val.bitrateKbps)
        case .variableBitrate(let val):
            self.quality = .variableBitrate(
                targetBitrateKbps: val.targetBitrateKbps,
                maxBitrateKbps: val.maxBitrateKbps
            )
        case .auto:
            self.quality = .auto
        case .none:
            throw SiriusMessageError.invalidProtobufMessage
        }

        self.sampleRate = protobufMessage.sampleRate != 0 ? protobufMessage.sampleRate : nil
        self.channelCount = protobufMessage.channelCount != 0 ? protobufMessage.channelCount : nil
        self.options = CodecOptionsParser.parse(optionsString: protobufMessage.hasOptions ? protobufMessage.options : nil)
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.fourCc = fourCC.rawValue

        switch quality {
        case .constantBitrate(let bitrateKbps):
            message.quality = .constantBitrate(.with {
                $0.bitrateKbps = bitrateKbps
            })
        case .variableBitrate(let targetBitrateKbps, let maxBitrateKbps):
            message.quality = .variableBitrate(.with {
                $0.targetBitrateKbps = targetBitrateKbps
                $0.maxBitrateKbps = maxBitrateKbps
            })
        case .auto:
            message.quality = .auto(.init())
        }

        if let sampleRate = sampleRate {
            message.sampleRate = sampleRate
        }
        if let channelCount = channelCount {
            message.channelCount = channelCount
        }

        message.options = CodecOptionsParser.serialize(options: options)

        return message
    }
}

// MARK: - AudioSource

public enum AudioSource {
    /// 세션 전역 오디오 루프백
    case sessionAudio

    /// 특정 애플리케이션의 오디오
    case applicationAudio(pid: UInt64?, bundleID: String?)

    /// 마이크 입력
    case microphone(deviceID: String?)

    init(from protobufMessage: Sirius_Msgdef_V1_Channels_Projection_AudioSource) throws {
        switch protobufMessage.value {
        case .sessionAudio:
            self = .sessionAudio
        case .applicationAudio(let app):
            switch app.identifier {
            case .pid(let pid):
                self = .applicationAudio(pid: pid, bundleID: nil)
            case .bundleID(let bundleID):
                self = .applicationAudio(pid: nil, bundleID: bundleID)
            case .none:
                self = .applicationAudio(pid: nil, bundleID: nil)
            }
        case .microphone(let mic):
            self = .microphone(deviceID: mic.hasDeviceID ? mic.deviceID : nil)
        case .none:
            throw SiriusMessageError.invalidProtobufMessage
        }
    }

    func toProtobufMessage() -> Sirius_Msgdef_V1_Channels_Projection_AudioSource {
        var message = Sirius_Msgdef_V1_Channels_Projection_AudioSource()

        switch self {
        case .sessionAudio:
            message.value = .sessionAudio(.init())
        case .applicationAudio(let pid, let bundleID):
            var app = Sirius_Msgdef_V1_Channels_Projection_ApplicationAudioSource()
            if let pid = pid {
                app.identifier = .pid(pid)
            } else if let bundleID = bundleID {
                app.identifier = .bundleID(bundleID)
            }
            message.value = .applicationAudio(app)
        case .microphone(let deviceID):
            var mic = Sirius_Msgdef_V1_Channels_Projection_MicrophoneAudioSource()
            if let deviceID = deviceID {
                mic.deviceID = deviceID
            }
            message.value = .microphone(mic)
        }

        return message
    }
}

// MARK: - Request Messages

public struct AudioProjectionRequest: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_AudioProjectionRequest

    public let identifier: UUID
    public let source: AudioSource
    public let preferredCodecs: [AudioCodec]

    public init(identifier: UUID, source: AudioSource, preferredCodecs: [AudioCodec]) {
        self.identifier = identifier
        self.source = source
        self.preferredCodecs = preferredCodecs
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.identifier = UUID(msgdef: protobufMessage.identifier)
        self.source = try AudioSource(from: protobufMessage.source)
        self.preferredCodecs = try protobufMessage.preferredCodecs.map { try AudioCodec(from: $0) }
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.identifier = identifier.asMsgDef()
        message.source = source.toProtobufMessage()
        message.preferredCodecs = preferredCodecs.map { $0.toProtobufMessage() }

        return message
    }
}

public struct StopAudioProjectionRequest: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_StopAudioProjectionRequest

    public let identifier: UUID

    public init(identifier: UUID) {
        self.identifier = identifier
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.identifier = UUID(msgdef: protobufMessage.identifier)
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.identifier = identifier.asMsgDef()

        return message
    }
}

// MARK: - Event Messages

public struct AudioSessionCreatedEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_AudioSessionCreatedEvent

    public let identifier: UUID
    public let source: AudioSource
    public let codec: AudioCodec

    public init(identifier: UUID, source: AudioSource, codec: AudioCodec) {
        self.identifier = identifier
        self.source = source
        self.codec = codec
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.identifier = UUID(msgdef: protobufMessage.identifier)
        self.source = try AudioSource(from: protobufMessage.source)
        self.codec = try AudioCodec(from: protobufMessage.codec)
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.identifier = identifier.asMsgDef()
        message.source = source.toProtobufMessage()
        message.codec = codec.toProtobufMessage()

        return message
    }
}

public struct AudioSessionCreationFailedEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_AudioSessionCreationFailedEvent

    public let identifier: UUID
    public let reason: AudioSessionFailureReason
    public let message: String?

    public init(identifier: UUID, reason: AudioSessionFailureReason, message: String? = nil) {
        self.identifier = identifier
        self.reason = reason
        self.message = message
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.identifier = UUID(msgdef: protobufMessage.identifier)
        self.reason = .fromProtobufEnum(protobufMessage.reason)
        self.message = protobufMessage.hasMessage ? protobufMessage.message : nil
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.identifier = identifier.asMsgDef()
        message.reason = reason.toProtobufEnum()
        if let msg = self.message {
            message.message = msg
        }

        return message
    }
}

public struct AudioSessionChangedEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_AudioSessionChangedEvent

    public let identifier: UUID
    public let reason: AudioSessionChangeReason
    public let source: AudioSource?
    public let codec: AudioCodec?

    public init(identifier: UUID, reason: AudioSessionChangeReason, source: AudioSource? = nil, codec: AudioCodec? = nil) {
        self.identifier = identifier
        self.reason = reason
        self.source = source
        self.codec = codec
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.identifier = UUID(msgdef: protobufMessage.identifier)
        self.reason = .fromProtobufEnum(protobufMessage.reason)
        self.source = protobufMessage.hasSource ? try AudioSource(from: protobufMessage.source) : nil
        self.codec = protobufMessage.hasCodec ? try AudioCodec(from: protobufMessage.codec) : nil
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.identifier = identifier.asMsgDef()
        message.reason = reason.toProtobufEnum()
        if let source = source {
            message.source = source.toProtobufMessage()
        }
        if let codec = codec {
            message.codec = codec.toProtobufMessage()
        }

        return message
    }
}

public struct AudioSessionEndedEvent: SiriusMessage {
    typealias ProtobufMessage = Sirius_Msgdef_V1_Channels_Projection_AudioSessionEndedEvent

    public let identifier: UUID
    public let reason: AudioSessionEndReason
    public let message: String?

    public init(identifier: UUID, reason: AudioSessionEndReason, message: String? = nil) {
        self.identifier = identifier
        self.reason = reason
        self.message = message
    }

    init(from protobufMessage: ProtobufMessage) throws {
        self.identifier = UUID(msgdef: protobufMessage.identifier)
        self.reason = .fromProtobufEnum(protobufMessage.reason)
        self.message = protobufMessage.hasMessage ? protobufMessage.message : nil
    }

    func toProtobufMessage() -> ProtobufMessage {
        var message = ProtobufMessage()

        message.identifier = identifier.asMsgDef()
        message.reason = reason.toProtobufEnum()
        if let msg = self.message {
            message.message = msg
        }

        return message
    }
}
