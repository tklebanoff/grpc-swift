// swift-tools-version:5.3
/*
 * Copyright 2017, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.

 */
import PackageDescription

let package = Package(
    name: "grpc-swift",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "GRPC", 
            targets: ["GRPC"]
            ),
        .library(name: "CGRPCZlib", targets: ["CGRPCZlib"]),
        .executable(name: "protoc-gen-grpc-swift", targets: ["protoc-gen-grpc-swift"]),
    ],

    dependencies: [

        // GRPC dependencies:
        // Main SwiftNIO package
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.22.0"),

        // HTTP2 via SwiftNIO
        .package(url: "https://github.com/apple/swift-nio-http2.git", from: "1.14.1"),

        // TLS via SwiftNIO
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.8.0"),

        // Support for Network.framework where possible.
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", from: "1.6.0"),

        // Official SwiftProtobuf library, for [de]serializing data to send on the wire.
        .package(name: "SwiftProtobuf", url: "https://github.com/apple/swift-protobuf.git", from: "1.9.0"),

        // Logging API.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.4.0"),

    ],
    targets: [
        // The main GRPC module.
        .target(
            name: "GRPC",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
                .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOHTTP2", package: "swift-nio-http2"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "SwiftProtobufPluginLibrary", package: "SwiftProtobuf"),
                .product(name: "protoc-gen-swift", package: "SwiftProtobuf"),
                "CGRPCZlib",
            ]
            ), 
        .target(
            name: "CGRPCZlib",
            linkerSettings: [
                .linkedLibrary("z"),
            ]
            ),

        // The `protoc` plugin.
        .target(
            name: "protoc-gen-grpc-swift",
            dependencies: [
                "SwiftProtobuf",
                //"SwiftProtobufPluginLibrary",
                .product(name: "SwiftProtobufPluginLibrary", package: "SwiftProtobuf"),
                .product(name: "protoc-gen-swift", package: "SwiftProtobuf"),
                //"protoc-gen-swift",
            ]
            ),

    ]
)
