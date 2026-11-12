/**
 * File: LoopbackWebServer.swift
 * -----------------------------
 * Layer: Tests
 * Description: A small web server on the loopback address, inside the test, so a test of a web view never loads a page
 *              from the internet.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import Foundation
import Network
import Synchronization

/// Serves fixed pages by path at `http://127.0.0.1:<port>/`, bound to the loopback address only, and records the paths
/// asked for, so a test can tell which pages a web view loaded and when. A path it does not know answers 404. Pages must
/// hold no audio or video: nothing a test loads may play a sound. The hosted iPad target compiles this file as one of
/// its own sources.
public final class LoopbackWebServer {
    public let port: UInt16
    private let listener: NWListener
    private let requests: LockedLog

    /// The paths asked for so far, in order.
    public var requestedPaths: [String] { requests.entries }

    /// Starts the server with `pages`, HTML by path (`/grapher`).
    public init(pages: [String: String]) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let requests = LockedLog()
        let queue = DispatchQueue(label: "LoopbackWebServer")
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let requestLine = data.flatMap { bytes in String(data: bytes, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
                let parts = requestLine.split(separator: " ")
                let path = parts.count >= 2 ? String(parts[1]) : "/"
                requests.append(path)
                let page = pages[path]
                let body = Data((page ?? "<html><body>Not found</body></html>").utf8)
                let head = "HTTP/1.1 \(page == nil ? "404 Not Found" : "200 OK")\r\nContent-Type: text/html; charset=utf-8\r\n"
                    + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let starts = LockedLog()
        port = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard starts.appendFirst("ready") else { return }
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    guard starts.appendFirst("failed") else { return }
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        self.listener = listener
        self.requests = requests
    }

    /// The address of `path` on this server.
    public func address(_ path: String) -> URL {
        URL(string: "http://127.0.0.1:\(port)\(path)") ?? URL(fileURLWithPath: "/")
    }

    public func stop() {
        listener.cancel()
    }
}

/// Lines written from the server's queue and read from the test's.
private final class LockedLog: Sendable {
    private let mutex = Mutex<[String]>([])

    var entries: [String] { mutex.withLock { entries in entries } }

    func append(_ entry: String) { mutex.withLock { entries in entries.append(entry) } }

    /// Appends `entry` only to an empty log, and tells whether it did.
    func appendFirst(_ entry: String) -> Bool {
        mutex.withLock { entries in
            guard entries.isEmpty else { return false }
            entries.append(entry)
            return true
        }
    }
}
