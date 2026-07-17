import Foundation
import Network

/// Minimal HTTP/1.1 server on `NWListener` (TCP, no WebSocket): parses the
/// request line, headers, and a `Content-Length` body, then hands
/// `(method, path, headers, body)` to a handler returning
/// `(status, headers, body)`. Every response carries `Connection: close` and
/// the socket is closed after it is written.
///
/// This replaces the `http.createServer` + `StreamableHTTPServerTransport`
/// stack from `reactotron-mcp/src/mcp-server.ts`. The MCP "streamable HTTP"
/// transport is, for a single non-streaming JSON-RPC exchange, just a POST
/// whose response body is one JSON object — which is exactly what this serves.
final class MinimalHTTPServer: @unchecked Sendable {
  typealias Handler = @Sendable (
    _ method: String, _ path: String, _ headers: [String: String], _ body: Data
  ) -> (Int, [String: String], Data)

  enum HTTPError: Error { case invalidPort, startTimeout }

  private let handler: Handler
  // Concurrent so a request that blocks (the wait-for-response tools poll for
  // up to 1.5s) doesn't stall other connections.
  private let queue = DispatchQueue(label: "com.reactotron.mcp.http", attributes: .concurrent)
  private var listener: NWListener?

  init(handler: @escaping Handler) {
    self.handler = handler
  }

  /// Binds and starts listening. Throws synchronously on bind failure
  /// (`EADDRINUSE` surfaces here as the underlying `NWError`) so the caller can
  /// surface "port in use" to the UI, matching `mcp-server.ts`'s rejected start
  /// promise.
  func start(port: UInt16) throws {
    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw HTTPError.invalidPort }

    let listener = try NWListener(using: params, on: nwPort)
    self.listener = listener

    let sem = DispatchSemaphore(value: 0)
    let errBox = ErrorBox()
    listener.stateUpdateHandler = { state in
      switch state {
      case .ready:
        sem.signal()
      case .failed(let error):
        errBox.error = error
        sem.signal()
      default:
        break
      }
    }
    listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
    listener.start(queue: queue)

    // Bind resolves in milliseconds; the 3s ceiling is only a safety net.
    if sem.wait(timeout: .now() + 3) == .timedOut {
      listener.cancel()
      self.listener = nil
      throw HTTPError.startTimeout
    }
    if let error = errBox.error {
      listener.cancel()
      self.listener = nil
      throw error
    }
  }

  func stop() {
    listener?.cancel()  // thread-safe; in-flight connections drain on their own
    listener = nil
  }

  // MARK: - Connection handling

  private func accept(_ conn: NWConnection) {
    conn.start(queue: queue)
    receive(conn, buffer: Data())
  }

  private func receive(_ conn: NWConnection, buffer: Data) {
    conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
      guard let self else { conn.cancel(); return }
      var buf = buffer
      if let data { buf.append(data) }

      if let (method, path, headers, body) = Self.parseRequest(buf) {
        let (status, respHeaders, respBody) = self.handler(method, path, headers, body)
        self.respond(conn, status: status, headers: respHeaders, body: respBody)
        return
      }

      if isComplete || error != nil {
        conn.cancel()
        return
      }
      self.receive(conn, buffer: buf)
    }
  }

  private static let headerTerminator = Data("\r\n\r\n".utf8)

  /// Returns `(method, path, headers, body)` once the buffer holds a complete
  /// request (headers + `Content-Length` bytes), otherwise `nil` (need more).
  /// Header names are lowercased for case-insensitive lookup.
  static func parseRequest(_ buf: Data) -> (String, String, [String: String], Data)? {
    guard let range = buf.range(of: headerTerminator) else { return nil }
    let headerData = buf.subdata(in: buf.startIndex..<range.lowerBound)
    guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }

    let lines = headerString.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else { return nil }
    let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count >= 2 else { return nil }
    let method = String(parts[0])
    let path = String(parts[1])

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      headers[name] = value
    }

    let contentLength = headers["content-length"].flatMap { Int($0) } ?? 0
    let bodyStart = range.upperBound
    let available = buf.endIndex - bodyStart
    if available < contentLength { return nil }
    let body = buf.subdata(in: bodyStart..<(bodyStart + contentLength))
    return (method, path, headers, body)
  }

  private func respond(_ conn: NWConnection, status: Int, headers: [String: String], body: Data) {
    var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
    var h = headers
    h["Content-Length"] = String(body.count)
    h["Connection"] = "close"
    for (key, value) in h {
      head += "\(key): \(value)\r\n"
    }
    head += "\r\n"

    var out = Data(head.utf8)
    out.append(body)
    conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
  }

  private static func reason(_ status: Int) -> String {
    switch status {
    case 200: "OK"
    case 202: "Accepted"
    case 204: "No Content"
    case 400: "Bad Request"
    case 404: "Not Found"
    case 405: "Method Not Allowed"
    case 500: "Internal Server Error"
    default: "OK"
    }
  }
}

/// Carries an `NWError` out of the state-update closure to `start(port:)`.
private final class ErrorBox: @unchecked Sendable {
  var error: NWError?
}
