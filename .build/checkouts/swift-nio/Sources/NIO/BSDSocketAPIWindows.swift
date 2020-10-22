//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//
#if os(Windows)
import ucrt

import let WinSDK.AF_INET
import let WinSDK.AF_INET6
import let WinSDK.AF_UNIX

import let WinSDK.IPPROTO_IP
import let WinSDK.IPPROTO_IPV6
import let WinSDK.IPPROTO_TCP

import let WinSDK.IP_ADD_MEMBERSHIP
import let WinSDK.IP_DROP_MEMBERSHIP
import let WinSDK.IP_MULTICAST_IF
import let WinSDK.IP_MULTICAST_LOOP
import let WinSDK.IP_MULTICAST_TTL

import let WinSDK.IPV6_JOIN_GROUP
import let WinSDK.IPV6_LEAVE_GROUP
import let WinSDK.IPV6_MULTICAST_HOPS
import let WinSDK.IPV6_MULTICAST_IF
import let WinSDK.IPV6_MULTICAST_LOOP
import let WinSDK.IPV6_V6ONLY

import let WinSDK.PF_INET
import let WinSDK.PF_INET6
import let WinSDK.PF_UNIX

import let WinSDK.TCP_NODELAY

import let WinSDK.SO_ERROR
import let WinSDK.SO_KEEPALIVE
import let WinSDK.SO_LINGER
import let WinSDK.SO_RCVBUF
import let WinSDK.SO_RCVTIMEO
import let WinSDK.SO_REUSEADDR
import let WinSDK.SO_REUSE_UNICASTPORT

import let WinSDK.SOL_SOCKET

import let WinSDK.SOCK_DGRAM
import let WinSDK.SOCK_STREAM

import let WinSDK.SOCKET_ERROR

import func WinSDK.WSAGetLastError

import struct WinSDK.socklen_t
import struct WinSDK.SOCKADDR


extension Shutdown {
    internal var cValue: CInt {
        switch self {
        case .RD:
            return WinSDK.SD_RECEIVE
        case .WR:
            return WinSDK.SD_SEND
        case .RDWR:
            return WinSDK.SD_BOTH
        }
    }
}

// MARK: _BSDSocketProtocol implementation
extension NIOBSDSocket {
    @inline(never)
    static func accept(socket s: NIOBSDSocket.Handle,
                       address addr: UnsafeMutablePointer<sockaddr>?,
                       address_len addrlen: UnsafeMutablePointer<socklen_t>?) throws -> NIOBSDSocket.Handle? {
        let socket: NIOBSDSocket.Handle = WinSDK.accept(s, addr, addrlen)
        if socket == WinSDK.INVALID_SOCKET {
            throw IOError(winsock: WSAGetLastError(), reason: "accept")
        }
        return socket
    }

    @inline(never)
    static func bind(socket s: NIOBSDSocket.Handle,
                     address addr: UnsafePointer<sockaddr>,
                     address_len namelen: socklen_t) throws {
        if WinSDK.bind(s, addr, namelen) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "bind")
        }
    }

    @inline(never)
    static func close(socket s: NIOBSDSocket.Handle) throws {
        try Posix.close(descriptor: s)
    }

    @inline(never)
    static func connect(socket s: NIOBSDSocket.Handle,
                        address name: UnsafePointer<sockaddr>,
                        address_len namelen: socklen_t) throws -> Bool {
        if WinSDK.connect(s, name, namelen) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "connect")
        }
        return true
    }

    @inline(never)
    static func getpeername(socket s: NIOBSDSocket.Handle,
                            address name: UnsafeMutablePointer<sockaddr>,
                            address_len namelen: UnsafeMutablePointer<socklen_t>) throws {
        if WinSDK.getpeername(s, name, namelen) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "getpeername")
        }
    }

    @inline(never)
    static func getsockname(socket s: NIOBSDSocket.Handle,
                            address name: UnsafeMutablePointer<sockaddr>,
                            address_len namelen: UnsafeMutablePointer<socklen_t>) throws {
        if WinSDK.getsockname(s, name, namelen) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "getsockname")
        }
    }

    @inline(never)
    static func getsockopt(socket: NIOBSDSocket.Handle,
                           level: NIOBSDSocket.OptionLevel,
                           option_name optname: NIOBSDSocket.Option,
                           option_value optval: UnsafeMutableRawPointer,
                           option_len optlen: UnsafeMutablePointer<socklen_t>) throws {
        if CNIOWindows_getsockopt(socket, level.rawValue, optname.rawValue,
                                  optval, optlen) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "getsockopt")
        }
    }

    @inline(never)
    static func listen(socket s: NIOBSDSocket.Handle, backlog: CInt) throws {
        if WinSDK.listen(s, backlog) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "listen")
        }
    }

    @inline(never)
    static func recv(socket s: NIOBSDSocket.Handle,
                     buffer buf: UnsafeMutableRawPointer,
                     length len: size_t) throws -> IOResult<size_t> {
        let iResult: CInt = CNIOWindows_recv(s, buf, CInt(len), 0)
        if iResult == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "recv")
        }
        return .processed(size_t(iResult))
    }

    @inline(never)
    static func recvmsg(descriptor: CInt, msgHdr: UnsafeMutablePointer<msghdr>, flags: CInt) throws -> IOResult<ssize_t> {
        fatalError("recvmsg not yet implemented on Windows")
    }
    
    @inline(never)
    static func sendmsg(descriptor: CInt,
                        msgHdr: UnsafePointer<msghdr>,
                        flags: CInt) throws -> IOResult<ssize_t> {
        fatalError("recvmsg not yet implemented on Windows")
    }

    @inline(never)
    static func send(socket s: NIOBSDSocket.Handle,
                     buffer buf: UnsafeRawPointer,
                     length len: size_t) throws -> IOResult<size_t> {
        let iResult: CInt = CNIOWindows_send(s, buf, CInt(len), 0)
        if iResult == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "send")
        }
        return .processed(size_t(iResult))
    }

    @inline(never)
    static func setsockopt(socket: NIOBSDSocket.Handle,
                           level: NIOBSDSocket.OptionLevel,
                           option_name optname: NIOBSDSocket.Option,
                           option_value optval: UnsafeRawPointer,
                           option_len optlen: socklen_t) throws {
        if CNIOWindows_setsockopt(socket, level.rawValue, optname.rawValue,
                                  optval, optlen) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "setsockopt")
        }
    }

    @inline(never)
    static func shutdown(socket: NIOBSDSocket.Handle, how: Shutdown) throws {
        if WinSDK.shutdown(socket, how.cValue) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "shutdown")
        }
    }

    @inline(never)
    static func socket(domain af: NIOBSDSocket.ProtocolFamily,
                       type: NIOBSDSocket.SocketType,
                       `protocol`: CInt) throws -> NIOBSDSocket.Handle {
        let socket: NIOBSDSocket.Handle = WinSDK.socket(af.rawValue, type.rawValue, `protocol`)
        if socket == WinSDK.INVALID_SOCKET {
            throw IOError(winsock: WSAGetLastError(), reason: "socket")
        }
        return socket
    }

    @inline(never)
    static func recvmmsg(socket: NIOBSDSocket.Handle,
                         msgvec: UnsafeMutablePointer<MMsgHdr>,
                         vlen: CUnsignedInt,
                         flags: CInt,
                         timeout: UnsafeMutablePointer<timespec>?) throws -> IOResult<Int> {
        return try Posix.recvmmsg(sockfd: socket,
                                  msgvec: msgvec,
                                  vlen: vlen,
                                  flags: flags,
                                  timeout: timeout)
    }

    @inline(never)
    static func sendmmsg(socket: NIOBSDSocket.Handle,
                         msgvec: UnsafeMutablePointer<MMsgHdr>,
                         vlen: CUnsignedInt,
                         flags: CInt) throws -> IOResult<Int> {
        return try Posix.sendmmsg(sockfd: socket,
                                  msgvec: msgvec,
                                  vlen: vlen,
                                  flags: flags)
    }

    // NOTE: this should return a `ssize_t`, however, that is not a standard
    // type, and defining that type is difficult.  Opt to return a `size_t`
    // which is the same size, but is unsigned.
    @inline(never)
    static func pread(socket: NIOBSDSocket.Handle,
                      pointer: UnsafeMutableRawPointer,
                      size: size_t,
                      offset: off_t) throws -> IOResult<size_t> {
        var ovlOverlapped: OVERLAPPED = OVERLAPPED()
        ovlOverlapped.OffsetHigh = DWORD(UInt32(offset >> 32) & 0xffffffff)
        ovlOverlapped.Offset = DWORD(UInt32(offset >> 0) & 0xffffffff)
        var nNumberOfBytesRead: DWORD = 0
        if !ReadFile(HANDLE(bitPattern: UInt(socket)), pointer, DWORD(size),
                     &nNumberOfBytesRead, &ovlOverlapped) {
            throw IOError(windows: GetLastError(), reason: "ReadFile")
        }
        return .processed(CInt(nNumberOfBytesRead))
    }

    // NOTE: this should return a `ssize_t`, however, that is not a standard
    // type, and defining that type is difficult.  Opt to return a `size_t`
    // which is the same size, but is unsigned.
    @inline(never)
    static func pwrite(socket: NIOBSDSocket.Handle,
                       pointer: UnsafeRawPointer,
                       size: size_t,
                       offset: off_t) throws -> IOResult<size_t> {
        var ovlOverlapped: OVERLAPPED = OVERLAPPED()
        ovlOverlapped.OffsetHigh = DWORD(UInt32(offset >> 32) & 0xffffffff)
        ovlOverlapped.Offset = DWORD(UInt32(offset >> 0) & 0xffffffff)
        var nNumberOfBytesWritten: DWORD = 0
        if !WriteFile(HANDLE(bitPattern: UInt(socket)), pointer, DWORD(size),
                      &nNumberOfBytesWritten, &ovlOverlapped) {
            throw IOError(windows: GetLastError(), reason: "WriteFile")
        }
        return .processed(CInt(nNumberOfBytesWritten))
    }

    @inline(never)
    static func poll(fds: UnsafeMutablePointer<pollfd>,
                     nfds: nfds_t,
                     timeout: CInt) throws -> CInt {
        fatalError("Poll unsupported on Windows")
    }

    @discardableResult
    @inline(never)
    static func inet_ntop(af family: NIOBSDSocket.AddressFamily,
                          src addr: UnsafeRawPointer,
                          dst dstBuf: UnsafeMutablePointer<CChar>,
                          size dstSize: socklen_t) throws -> UnsafePointer<CChar>? {
        // TODO(compnerd) use `InetNtopW` to ensure that we handle unicode properly
        guard let result = WinSDK.inet_ntop(family.rawValue, addr, dstBuf,
                                            Int(dstSize)) else {
            throw IOError(windows: GetLastError(), reason: "inet_ntop")
        }
        return result
    }

    @discardableResult
    @inline(never)
    static func inet_pton(af family: NIOBSDSocket.AddressFamily,
                          src description: UnsafePointer<CChar>,
                          dst address: UnsafeMutableRawPointer) throws {
        // TODO(compnerd) use `InetPtonW` to ensure that we handle unicode properly
         switch WinSDK.inet_pton(family.rawValue, description, address) {
         case 0: throw IOError(errnoCode: EINVAL, reason: "inet_pton")
         case 1: return
         default: throw IOError(winsock: WSAGetLastError(), reason: "inet_pton")
         }
    }

    @inline(never)
    static func sendfile(socket s: NIOBSDSocket.Handle,
                         fd: CInt,
                         offset: off_t,
                         len: off_t) throws -> IOResult<Int> {
        let hFile: HANDLE = HANDLE(bitPattern: ucrt._get_osfhandle(fd))!
        if hFile == INVALID_HANDLE_VALUE {
            throw IOError(errnoCode: EBADF, reason: "_get_osfhandle")
        }

        var ovlOverlapped: OVERLAPPED = OVERLAPPED()
        ovlOverlapped.Offset = DWORD(UInt32(offset >> 0) & 0xffffffff)
        ovlOverlapped.OffsetHigh = DWORD(UInt32(offset >> 32) & 0xffffffff)
        if !TransmitFile(s, hFile, DWORD(nNumberOfBytesToWrite), 0,
                         &ovlOverlapped, nil, DWORD(TF_USE_KERNEL_APC)) {
            throw IOError(winsock: WSAGetLastError(), reason: "TransmitFile")
        }

        return .processed(Int(nNumberOfBytesToWrite))
    }

    @inline(never)
    static func setNonBlocking(socket: NIOBSDSocket.Handle) throws {
        var ulMode: u_long = 1
        if WinSDK.ioctlsocket(socket, FIONBIO, &ulMode) == SOCKET_ERROR {
            throw IOError(winsock: WSAGetLastError(), reason: "ioctlsocket")
        }
    }
}


#endif
