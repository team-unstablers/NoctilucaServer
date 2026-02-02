//
//  ChannelOpenHelper.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import SwiftProtobuf

internal class ChannelOpenTask {
    var logger: SiriusLogger?
    
    let stream: Stream
    let timeout: TimeInterval
    
    init(stream: Stream, timeout: TimeInterval) {
        self.stream = stream
        self.timeout = timeout
    }
    
    func send(opcode: MessageOpcode, message: (any SiriusMessage)) async throws {
        let protobufMessage = message.toProtobufMessage()
        let messageData = try protobufMessage.serializedData()
        
        self.logger?.trace("frame SEND - opcode \(opcode.hexString), length \(messageData.count)")

        let result = await self.stream.write(frame: messageData, opcode: opcode)
        
        if case .failure(let error) = result {
            throw error
        }
    }

    func blockUntilReceiveData(timeout: TimeInterval? = nil) async throws -> SiriusFrame {
        let effectiveTimeout = timeout ?? self.timeout
        if effectiveTimeout <= 0 || !effectiveTimeout.isFinite {
            return try await Self.waitForFrame(stream: stream, logger: logger)
        }
        
        return try await withThrowingTaskGroup(of: SiriusFrame.self) { group in
            group.addTask { [stream = self.stream, logger = self.logger] in
                return try await Self.waitForFrame(stream: stream, logger: logger)
            }
            group.addTask { [logger = self.logger] in
                let timeoutNanoseconds = UInt64(effectiveTimeout * 1_000_000_000)
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                let timeoutMs = Int(effectiveTimeout * 1000)
                logger?.warning("channel open timed out while waiting for frame (timeout_ms=\(timeoutMs))")
                throw ChannelManagerError.channelOpenTimedOut
            }

            do {
                guard let frame = try await group.next() else {
                    throw ChannelManagerError.channelOpenFailed
                }

                group.cancelAll()
                return frame
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    private static func waitForFrame(stream: Stream, logger: SiriusLogger?) async throws -> SiriusFrame {
        for await event in stream.events {
            switch (event) {
            case .frame(let frame):
                logger?.trace("frame RECV - opcode \(frame.opcode.hexString), length \(frame.length)")
                return frame
            case .error(let error):
                logger?.error("caught error while waiting for data: \(error)")
                throw ChannelManagerError.channelOpenFailed
            case .closed:
                logger?.error("stream closed while waiting for data")
                throw ChannelManagerError.channelOpenFailed
            }
        }
        
        throw ChannelManagerError.channelOpenFailed
    }
}

internal class RemoteChannelOpenTask: ChannelOpenTask {
    
    override init(stream: Stream, timeout: TimeInterval) {
        super.init(stream: stream, timeout: timeout)
        
        self.logger = SiriusLogger(category: "RemoteChannelOpenTask")
    }
    
    func perform(_ channelCreationBlock: ((ChannelStartRequest) async throws -> Bool)) async throws {
        self.logger?.info("performing remote channel open task - waiting for channel start request")
        
        let frame: SiriusFrame
        do {
            frame = try await self.blockUntilReceiveData()
        } catch {
            if case ChannelManagerError.channelOpenTimedOut = error {
                try? await stream.close()
            }
            throw error
        }
        
        guard frame.isValid(),
              frame.opcode == .channelStartRequest,
              let request = try? ChannelStartRequest.fromProtobufBytes(frame.data)
        else {
            throw ChannelManagerError.channelOpenFailed
        }
        
        do {
            let isSuccess = try await channelCreationBlock(request)
            
            let response = ChannelStartResponse(success: isSuccess)
            try await self.send(opcode: .channelStartResponse, message: response)
        } catch {
            // FIXME: error handling
            let response = ChannelStartResponse(success: false)
            try await self.send(opcode: .channelStartResponse, message: response)
        }
        
    }
}

internal class LocalChannelOpenTask: ChannelOpenTask {
    let feature: SiriusFeature
    let identifier: ChannelIdentifier
    let args: [String]
    
    init(for feature: SiriusFeature,
         using stream: Stream,
         identifier: ChannelIdentifier,
         args: [String],
         timeout: TimeInterval)
    {
        self.feature = feature
        self.identifier = identifier
        self.args = args
        
        super.init(stream: stream, timeout: timeout)
        
        self.logger = SiriusLogger(category: "LocalChannelOpenTask")
    }
    
    func perform() async throws {
        self.logger?.info("performing local channel open task - feature \(self.feature.rawValue), channel \(self.identifier)")
        
        let request = ChannelStartRequest(
            featureID: feature.rawValue,
            channelID: identifier,
            args: args
        )
        
        try await self.send(opcode: .channelStartRequest, message: request)
        
        let frame: SiriusFrame
        do {
            frame = try await self.blockUntilReceiveData()
        } catch {
            if case ChannelManagerError.channelOpenTimedOut = error {
                try? await stream.close()
            }
            throw error
        }

        guard frame.isValid(),
              frame.opcode == .channelStartResponse,
              let response = try? ChannelStartResponse.fromProtobufBytes(frame.data)
        else {
            throw ChannelManagerError.channelOpenFailed
        }
        
        guard response.success else {
            throw ChannelManagerError.channelOpenFailed
        }
    }
}
