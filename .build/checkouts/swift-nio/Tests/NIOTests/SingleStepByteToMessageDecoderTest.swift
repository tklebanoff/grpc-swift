//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2017-2018 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

//
import XCTest
@testable import NIO

public final class NIOSingleStepByteToMessageDecoderTest: XCTestCase {
    private final class ByteToInt32Decoder: NIOSingleStepByteToMessageDecoder {
        typealias InboundOut = Int32

        func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
            return buffer.readInteger()
        }

        func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
            XCTAssertTrue(seenEOF)
            return try self.decode(buffer: &buffer)
        }
    }

    private final class ForeverDecoder: NIOSingleStepByteToMessageDecoder {
        typealias InboundOut = Never

        func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
            return nil
        }

        func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
            XCTAssertTrue(seenEOF)
            return try self.decode(buffer: &buffer)
        }
    }

    private final class LargeChunkDecoder: NIOSingleStepByteToMessageDecoder {
        typealias InboundOut = ByteBuffer

        func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
            return buffer.readSlice(length: 512)
        }

        func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
            XCTAssertFalse(seenEOF)
            return try self.decode(buffer: &buffer)
        }
    }

    // A special case decoder that decodes only once there is 5,120 bytes in the buffer,
    // at which point it decodes exactly 2kB of memory.
    private final class OnceDecoder: NIOSingleStepByteToMessageDecoder {
        typealias InboundOut = ByteBuffer

        func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
            guard buffer.readableBytes >= 5120 else {
                return nil
            }

            return buffer.readSlice(length: 2048)!
        }

        func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
            XCTAssertFalse(seenEOF)
            return try self.decode(buffer: &buffer)
        }
    }

    private final class PairOfBytesDecoder: NIOSingleStepByteToMessageDecoder {
        typealias InboundOut = ByteBuffer

        var decodeLastCalls = 0
        var lastBuffer: ByteBuffer?

        func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
            return buffer.readSlice(length: 2)
        }

        func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
            self.decodeLastCalls += 1
            XCTAssertEqual(1, self.decodeLastCalls)
            self.lastBuffer = buffer
            return nil
        }
    }

    private final class MessageReceiver<InboundOut> {
        var messages: CircularBuffer<InboundOut> = CircularBuffer()

        func receiveMessage(message: InboundOut) {
            messages.append(message)
        }

        var count: Int { return messages.count }

        func retrieveMessage() -> InboundOut? {
            if messages.isEmpty {
                return nil
            }
            return messages.removeFirst()
        }
    }

    func testDecoder() throws {
        let allocator = ByteBufferAllocator()
        let processor = NIOSingleStepByteToMessageProcessor(ByteToInt32Decoder())
        let messageReceiver: MessageReceiver<Int32> = MessageReceiver()

        var buffer = allocator.buffer(capacity: 32)
        buffer.writeInteger(Int32(1))
        let writerIndex = buffer.writerIndex
        buffer.moveWriterIndex(to: writerIndex - 1)

        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        XCTAssertNil(messageReceiver.retrieveMessage())

        buffer.moveWriterIndex(to: writerIndex)
        XCTAssertNoThrow(try processor.process(buffer: buffer.getSlice(at: writerIndex - 1, length: 1)!, messageReceiver.receiveMessage))

        var buffer2 = allocator.buffer(capacity: 32)
        buffer2.writeInteger(Int32(2))
        buffer2.writeInteger(Int32(3))
        XCTAssertNoThrow(try processor.process(buffer: buffer2, messageReceiver.receiveMessage))

        XCTAssertNoThrow(try processor.finishProcessing(seenEOF: true, messageReceiver.receiveMessage))

        XCTAssertEqual(Int32(1), messageReceiver.retrieveMessage())
        XCTAssertEqual(Int32(2), messageReceiver.retrieveMessage())
        XCTAssertEqual(Int32(3), messageReceiver.retrieveMessage())
        XCTAssertNil(messageReceiver.retrieveMessage())
    }

    func testMemoryIsReclaimedIfMostIsConsumed() throws {
        let allocator = ByteBufferAllocator()
        let processor = NIOSingleStepByteToMessageProcessor(LargeChunkDecoder())
        let messageReceiver: MessageReceiver<ByteBuffer> = MessageReceiver()
        defer {
            XCTAssertNoThrow(try processor.finishProcessing(seenEOF: false, messageReceiver.receiveMessage))
        }

        // We're going to send in 513 bytes. This will cause a chunk to be passed on, and will leave
        // a 512-byte empty region in a 513 byte buffer. This will not cause a shrink.
        var buffer = allocator.buffer(capacity: 513)
        buffer.writeBytes(Array(repeating: 0x04, count: 513))
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))

        XCTAssertEqual(512, messageReceiver.retrieveMessage()!.readableBytes)

        XCTAssertEqual(1, processor._buffer!.readableBytes)
        XCTAssertEqual(512, processor._buffer!.readerIndex)

        // Now we're going to send in another 513 bytes. This will cause another chunk to be passed in,
        // but now we'll shrink the buffer.
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))

        XCTAssertEqual(2, processor._buffer!.readableBytes)
        XCTAssertEqual(0, processor._buffer!.readerIndex)
    }

    func testMemoryIsReclaimedIfLotsIsAvailable() throws {
        let allocator = ByteBufferAllocator()
        let processor = NIOSingleStepByteToMessageProcessor(OnceDecoder())
        let messageReceiver: MessageReceiver<ByteBuffer> = MessageReceiver()
        defer {
            XCTAssertNoThrow(try processor.finishProcessing(seenEOF: false, messageReceiver.receiveMessage))
        }

        // We're going to send in 5119 bytes. This will be held.
        var buffer = allocator.buffer(capacity: 5119)
        buffer.writeBytes(Array(repeating: 0x04, count: 5119))
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        XCTAssertEqual(0, messageReceiver.count)

        XCTAssertEqual(5119, processor._buffer!.readableBytes)
        XCTAssertEqual(0, processor._buffer!.readerIndex)

        // Now we're going to send in one more byte. This will cause a chunk to be passed on,
        // shrinking the held memory to 3072 bytes. However, memory will be reclaimed.
        XCTAssertNoThrow(try processor.process(buffer: buffer.getSlice(at: 0, length: 1)!, messageReceiver.receiveMessage))
        XCTAssertEqual(2048, messageReceiver.retrieveMessage()!.readableBytes)
        XCTAssertEqual(3072, processor._buffer!.readableBytes)
        XCTAssertEqual(0, processor._buffer!.readerIndex)
    }

    func testLeftOversMakeDecodeLastCalled() {
        let allocator = ByteBufferAllocator()
        let decoder = PairOfBytesDecoder()
        let processor = NIOSingleStepByteToMessageProcessor(decoder)
        let messageReceiver: MessageReceiver<ByteBuffer> = MessageReceiver()

        var buffer = allocator.buffer(capacity: 16)
        buffer.clear()
        buffer.writeStaticString("1")
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        buffer.clear()
        buffer.writeStaticString("23")
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        buffer.clear()
        buffer.writeStaticString("4567890x")
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        XCTAssertNoThrow(try processor.finishProcessing(seenEOF: false, messageReceiver.receiveMessage))

        XCTAssertEqual("12", messageReceiver.retrieveMessage().map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        })
        XCTAssertEqual("34", messageReceiver.retrieveMessage().map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        })
        XCTAssertEqual("56", messageReceiver.retrieveMessage().map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        })
        XCTAssertEqual("78", messageReceiver.retrieveMessage().map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        })
        XCTAssertEqual("90", messageReceiver.retrieveMessage().map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        })
        XCTAssertNil(messageReceiver.retrieveMessage())

        XCTAssertEqual("x", decoder.lastBuffer.map {
            String(decoding: $0.readableBytesView, as: Unicode.UTF8.self)
        })
        XCTAssertEqual(1, decoder.decodeLastCalls)
    }

    func testStructsWorkAsOSBTMDecoders() {
        struct WantsOneThenTwoOSBTMDecoder: NIOSingleStepByteToMessageDecoder {
            typealias InboundOut = Int

            var state: Int = 1

            mutating func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
                if buffer.readSlice(length: self.state) != nil {
                    defer {
                        self.state += 1
                    }
                    return self.state
                } else {
                    return nil
                }
            }

            mutating func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
                XCTAssertTrue(seenEOF)
                if self.state > 0 {
                    self.state = 0
                    return buffer.readableBytes * -1
                } else {
                    return nil
                }
            }
        }
        let allocator = ByteBufferAllocator()
        let processor = NIOSingleStepByteToMessageProcessor(WantsOneThenTwoOSBTMDecoder())
        let messageReceiver: MessageReceiver<Int> = MessageReceiver()

        var buffer = allocator.buffer(capacity: 16)
        buffer.clear()
        buffer.writeStaticString("1")
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        buffer.clear()
        buffer.writeStaticString("23")
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        buffer.clear()
        buffer.writeStaticString("4567890qwer")
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))

        XCTAssertEqual(1, messageReceiver.retrieveMessage())
        XCTAssertEqual(2, messageReceiver.retrieveMessage())
        XCTAssertEqual(3, messageReceiver.retrieveMessage())
        XCTAssertEqual(4, messageReceiver.retrieveMessage())
        XCTAssertNil(messageReceiver.retrieveMessage())

        XCTAssertNoThrow(try processor.finishProcessing(seenEOF: true, messageReceiver.receiveMessage))

        XCTAssertEqual(-4, messageReceiver.retrieveMessage())
        XCTAssertNil(messageReceiver.retrieveMessage())
    }

    func testDecodeLastIsInvokedOnceEvenIfNothingEverArrivedOnChannelClosed() {
        class Decoder: NIOSingleStepByteToMessageDecoder {
            typealias InboundOut = ()
            var decodeLastCalls = 0

            public func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
                XCTFail("did not expect to see decode called")
                return nil
            }

            public func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
                XCTAssertTrue(seenEOF)
                self.decodeLastCalls += 1
                XCTAssertEqual(1, self.decodeLastCalls)
                XCTAssertEqual(0, buffer.readableBytes)
                return ()
            }
        }

        let decoder = Decoder()
        let processor = NIOSingleStepByteToMessageProcessor(decoder)
        let messageReceiver: MessageReceiver<()> = MessageReceiver()

        XCTAssertEqual(0, messageReceiver.count)

        XCTAssertNoThrow(try processor.finishProcessing(seenEOF: true, messageReceiver.receiveMessage))
        XCTAssertNotNil(messageReceiver.retrieveMessage())
        XCTAssertNil(messageReceiver.retrieveMessage())

        XCTAssertEqual(1, decoder.decodeLastCalls)
    }

    func testPayloadTooLarge() {
        struct Decoder: NIOSingleStepByteToMessageDecoder {
            typealias InboundOut = Never

            func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
                return nil
            }

            func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
                return nil
            }
        }

        let max = 100
        let allocator = ByteBufferAllocator()
        let processor = NIOSingleStepByteToMessageProcessor(Decoder(), maximumBufferSize: max)
        let messageReceiver: MessageReceiver<Never> = MessageReceiver()

        var buffer = allocator.buffer(capacity: max + 1)
        buffer.writeString(String(repeating: "*", count: max + 1))
        XCTAssertThrowsError(try processor.process(buffer: buffer, messageReceiver.receiveMessage)) { error in
            XCTAssertTrue(error is ByteToMessageDecoderError.PayloadTooLargeError)
        }
    }

    func testPayloadTooLargeButHandlerOk() {
        class Decoder: NIOSingleStepByteToMessageDecoder {
            typealias InboundOut = String

            var decodeCalls = 0

            func decode(buffer: inout ByteBuffer) throws -> InboundOut? {
                self.decodeCalls += 1
                return buffer.readString(length: buffer.readableBytes)
            }

            func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> InboundOut? {
                return try decode(buffer: &buffer)
            }
        }

        let max = 100
        let allocator = ByteBufferAllocator()
        let decoder = Decoder()
        let processor = NIOSingleStepByteToMessageProcessor(decoder, maximumBufferSize: max)
        let messageReceiver: MessageReceiver<String> = MessageReceiver()

        var buffer = allocator.buffer(capacity: max + 1)
        buffer.writeString(String(repeating: "*", count: max + 1))
        XCTAssertNoThrow(try processor.process(buffer: buffer, messageReceiver.receiveMessage))
        XCTAssertNoThrow(try processor.finishProcessing(seenEOF: false, messageReceiver.receiveMessage))
        XCTAssertEqual(0, processor._buffer!.readableBytes)
        XCTAssertGreaterThan(decoder.decodeCalls, 0)
    }

    func testReentrancy() {
        class ReentrantWriteProducingHandler: ChannelInboundHandler {
            typealias InboundIn = ByteBuffer
            typealias InboundOut = String
            var processor: NIOSingleStepByteToMessageProcessor<OneByteStringDecoder>? = nil
            var produced = 0

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                if self.processor == nil {
                    self.processor = NIOSingleStepByteToMessageProcessor(OneByteStringDecoder())
                }
                do {
                    try self.processor!.process(buffer: self.unwrapInboundIn(data)) { message in
                        self.produced += 1
                        // Produce an extra write the first time we are called to test reentrancy
                        if self.produced == 1 {
                            let buf = ByteBuffer(string: "X")
                            XCTAssertNoThrow(try (context.channel as! EmbeddedChannel).writeInbound(buf))
                        }
                        context.fireChannelRead(self.wrapInboundOut(message))
                    }
                } catch {
                    context.fireErrorCaught(error)
                }
            }
        }

        class OneByteStringDecoder: NIOSingleStepByteToMessageDecoder {
            typealias InboundOut = String

            func decode(buffer: inout ByteBuffer) throws -> String? {
                return buffer.readString(length: 1)
            }

            func decodeLast(buffer: inout ByteBuffer, seenEOF: Bool) throws -> String? {
                XCTAssertTrue(seenEOF)
                return try self.decode(buffer: &buffer)
            }
        }

        let channel = EmbeddedChannel(handler: ReentrantWriteProducingHandler())
        var buffer = channel.allocator.buffer(capacity: 16)
        buffer.writeStaticString("a")
        XCTAssertNoThrow(try channel.writeInbound(buffer))
        XCTAssertNoThrow(XCTAssertEqual("X", try channel.readInbound()))
        XCTAssertNoThrow(XCTAssertEqual("a", try channel.readInbound()))
        XCTAssertNoThrow(XCTAssertTrue(try channel.finish().isClean))
    }
}
