import XCTest
@testable import Reactotron

/// Lazy payload subtrees (`JSONValue.raw` / `RawJSON` / `LazyJSONPolicy`):
/// a lazily parsed command must behave exactly like an eagerly parsed one
/// everywhere it's observed — equality, `SerializationRepair`, filterSearch,
/// Redaction/MCP output, wire sends — while hot paths never parse it.
final class RawJSONTests: XCTestCase {

  // MARK: - Helpers

  /// Every eligible container becomes raw (no size floor).
  private let maxLazy = LazyJSONPolicy(minBytes: 1)

  private func envelope(_ payload: String, type: String = "t") -> Data {
    Data(#"{"type":"\#(type)","payload":\#(payload)}"#.utf8)
  }

  /// `subtree` parsed as `payload.v` with every eligible container raw.
  private func raw(_ subtree: String, file: StaticString = #filePath, line: UInt = #line) -> RawJSON? {
    guard let v = JSONParser.parse(envelope(#"{"v":\#(subtree)}"#), lazy: maxLazy)?["payload"]?["v"],
      case .raw(let r) = v
    else {
      XCTFail("payload.v is not raw", file: file, line: line)
      return nil
    }
    return r
  }

  /// The server's receive pipeline (`ReactotronServer.handleMessage`):
  /// envelope parse, then `repairSerialization` on payload and diff.
  private func command(_ frame: String, lazy: LazyJSONPolicy?, id: Int = 1) -> Command {
    let m = WireMessage(data: Data(frame.utf8), lazy: lazy)!
    return Command(
      type: m.type, connectionId: 1, messageId: id, date: Date(timeIntervalSince1970: 0),
      deltaTime: m.deltaTime ?? 0, important: m.important?.isTruthy ?? false,
      payload: SerializationRepair.repair(m.payload ?? .null), clientId: "c",
      diff: m.diff.map(SerializationRepair.repair))
  }

  private func containsRaw(_ v: JSONValue) -> Bool {
    switch v {
    case .raw: true
    case .array(let a): a.contains(where: containsRaw)
    case .object(let o): o.values.contains(where: containsRaw)
    default: false
    }
  }

  private var materializeCount: Int { RawJSON.debugMaterializeCount.withLock { $0 } }

  /// The load script's (`scratchpad/load.mjs`) payload shapes, as
  /// `JSON.stringify` sends them.
  private static let loadBody: String = {
    let items = (0..<200).map {
      #"{"id":\#($0),"name":"item \#($0)","tags":["a","b"],"nested":{"x":\#($0),"y":"lorem ipsum dolor sit amet"}}"#
    }
    return #"{"items":[\#(items.joined(separator: ","))]}"#
  }()
  private static func loadItems(_ n: Int) -> String {
    let items = (0..<n).map {
      #"{"id":\#($0),"name":"item \#($0)","tags":["a","b"],"nested":{"x":\#($0),"y":"lorem ipsum dolor sit amet"}}"#
    }
    return "[\(items.joined(separator: ","))]"
  }
  private static let loadFrames: [String] = [
    #"{"type":"log","payload":{"level":"debug","message":"message 0 xxxxxxxx"},"important":false,"date":"2026-01-01T00:00:00.000Z","deltaTime":1}"#,
    #"{"type":"api.response","payload":{"duration":12,"request":{"url":"https://example.com/api/1","method":"GET","headers":{"a":"b"},"data":null,"params":null},"response":{"status":200,"headers":{"content-type":"application/json"},"body":\#(loadBody)}},"important":false,"deltaTime":1}"#,
    #"{"type":"state.action.complete","payload":{"name":"SOME_ACTION","action":{"type":"SOME_ACTION","payload":\#(loadItems(20))},"ms":1},"important":false,"deltaTime":1}"#,
    #"{"type":"display","payload":{"name":"DISPLAY","value":\#(loadItems(50)),"preview":"preview 3","important":false},"important":false,"deltaTime":1}"#,
  ]

  // MARK: - Policy

  func testLoadShapedPayloadsKeepSpineParsedAndBigSubtreesRaw() throws {
    let api = command(Self.loadFrames[1], lazy: .commandPayload)
    guard case .object(let request)? = api.payload["request"],
      case .object(let response)? = api.payload["response"],
      case .raw(let body)? = response["body"]
    else { return XCTFail("unexpected api.response shape: \(api.payload)") }
    XCTAssertEqual(request["method"], .string("GET"))
    XCTAssertTrue(body.isObject)
    XCTAssertEqual(body.count, 1)
    XCTAssertTrue(body.isCanonical)
    XCTAssertFalse(body.needsRepair)
    XCTAssertEqual(api.payload["response"]?["body"]?["items"]?[199]?["name"], .string("item 199"))

    let action = command(Self.loadFrames[2], lazy: .commandPayload)
    guard case .raw(let a)? = action.payload["action"] else { return XCTFail("action not raw") }
    XCTAssertTrue(a.isObject)
    XCTAssertEqual(a.count, 2)

    let display = command(Self.loadFrames[3], lazy: .commandPayload)
    guard case .raw(let v)? = display.payload["value"] else { return XCTFail("value not raw") }
    XCTAssertFalse(v.isObject)
    XCTAssertEqual(v.count, 50)

    // Spine keys stay parsed even when huge.
    let huge = #"{"type":"log","payload":{"message":\#(Self.loadBody),"changes":[{"path":"a","value":\#(Self.loadBody)}]}}"#
    let log = command(huge, lazy: .commandPayload)
    guard case .object(let message)? = log.payload["message"] else { return XCTFail("message not parsed") }
    guard case .raw? = message["items"] else { return XCTFail("message.items should be raw") }
    guard case .array(let changes)? = log.payload["changes"], case .object(let change)? = changes.first
    else { return XCTFail("changes / changes[*] not parsed") }
    guard case .raw? = change["value"] else { return XCTFail("changes[*].value should be raw") }
  }

  func testDiffRootAndEntriesStayParsed() throws {
    let frame = #"{"type":"state.action.complete","payload":{"name":"X"},"diff":[{"type":"CHANGE","path":["a"],"value":\#(Self.loadBody)}]}"#
    let c = command(frame, lazy: .commandPayload)
    guard case .array(let entries)? = c.diff, case .object(let entry)? = entries.first,
      case .raw? = entry["value"]
    else { return XCTFail("unexpected diff shape: \(String(describing: c.diff))") }
    XCTAssertEqual(DiffEntry.parse(c.diff).first?.pathText, "a")
  }

  /// `minBytes` is the subtree's exact byte length, brackets included.
  /// `reactotron-redux` (`sendAction.ts`) sends the diff *inside* the
  /// payload: `payload.diff` and its entries are spine like the envelope's
  /// `diff`, so the Diff tab never parses on redraw.
  func testPayloadLevelDiffRootAndEntriesStayParsed() throws {
    let frame = #"{"type":"state.action.complete","payload":{"name":"X","action":{"type":"X"},"ms":1,"diff":[{"type":"CHANGE","path":["a"],"value":\#(Self.loadBody),"oldValue":\#(Self.loadBody)},{"type":"CREATE","path":["b","0"],"value":1}]}}"#
    let c = command(frame, lazy: .commandPayload)
    guard case .array(let entries)? = c.payload["diff"], case .object(let entry)? = entries.first,
      case .raw? = entry["value"]
    else { return XCTFail("unexpected payload.diff shape: \(String(describing: c.payload["diff"]))") }
    let before = materializeCount
    for _ in 0..<3 {
      XCTAssertEqual(DiffEntry.parse(c.payload["diff"]).map(\.pathText), ["a", "b.0"])
    }
    XCTAssertEqual(materializeCount, before, "payload.diff must not be parsed per read")
  }

  /// filterSearch stringifies these paths on every keystroke, so a subtree
  /// there whose bytes can't be written verbatim (repair markers,
  /// non-canonical spelling) is parsed once at receive time instead of on
  /// every search. Off those paths it stays raw.
  func testSearchPathSubtreesThatCannotBeWrittenVerbatimAreParsedAtReceive() throws {
    let needsRepair = #"{"pad":"\#(String(repeating: "x", count: 2000))","u":"~~~ undefined ~~~"}"#
    let pretty = "{ \"pad\": \"\(String(repeating: "y", count: 2000))\" }"
    let frames = [
      #"{"type":"api.request","payload":{"request":{"url":"https://e.com","data":\#(needsRepair)}}}"#,
      #"{"type":"api.request","payload":{"request":{"url":"https://e.com","data":\#(pretty)}}}"#,
      #"{"type":"log","payload":{"message":{"ctx":\#(needsRepair)}}}"#,
      #"{"type":"display","payload":{"name":"N","preview":\#(pretty),"description":\#(needsRepair)}}"#,
    ]
    let commands = frames.enumerated().map { command($1, lazy: .commandPayload, id: $0) }
    for (frame, c) in zip(frames, commands) {
      XCTAssertFalse(containsRaw(c.payload), frame)
      XCTAssertEqual(c.payload, command(frame, lazy: nil).payload, frame)
    }
    XCTAssertEqual(commands[0].payload["request"]?["data"]?["u"], .null)
    let before = materializeCount
    XCTAssertEqual(filterSearch(commands, search: #""u":null"#).map(\.messageId), [0, 2, 3])
    XCTAssertEqual(materializeCount, before, "search must not parse")

    // Off the search paths the same subtrees stay raw (and repair lazily).
    let off = command(#"{"type":"display","payload":{"value":\#(needsRepair),"other":\#(pretty)}}"#, lazy: .commandPayload)
    guard case .raw(let v)? = off.payload["value"], case .raw(let o)? = off.payload["other"]
    else { return XCTFail("off-path subtrees should stay raw") }
    XCTAssertTrue(v.needsRepair)
    XCTAssertFalse(o.isCanonical)
    // A canonical, repair-free subtree on a search path stays raw too.
    let canonical = command(#"{"type":"log","payload":{"message":{"ctx":\#(Self.loadBody)}}}"#, lazy: .commandPayload)
    guard case .raw? = canonical.payload["message"]?["ctx"] else { return XCTFail("canonical ctx should be raw") }
  }

  /// JS `JSON.parse` keeps a repeated key's last value. A subtree with a
  /// duplicate key anywhere inside is parsed at receive time, so its count,
  /// search text and writes all agree with that parse.
  func testDuplicateKeysInsideLazySubtreesAreParsedEagerly() throws {
    let pad = String(repeating: "x", count: 1100)
    let many = (0..<40).map { #""k\#($0)":\#($0)"# }.joined(separator: ",")
    let duplicated = [
      #"{"a":"\#(pad)","a":1}"#,
      #"{"pad":"\#(pad)","x":[{"k":1,"k":2}]}"#,
      #"{"pad":"\#(pad)","a":1,"\u0061":2}"#,
      #"{"pad":"\#(pad)",\#(many),"k7":"again"}"#,  // past the linear-scan limit
    ]
    for subtree in duplicated {
      let frame = #"{"type":"display","payload":{"value":\#(subtree)}}"#
      let lazy = command(frame, lazy: .commandPayload)
      let eager = command(frame, lazy: nil)
      XCTAssertFalse(containsRaw(lazy.payload), subtree)
      XCTAssertEqual(lazy.payload, eager.payload, subtree)
      XCTAssertEqual(JSONWriter.stringify(lazy.payload), JSONWriter.stringify(eager.payload), subtree)
      XCTAssertEqual(lazy.payload["value"]?.containerCount, eager.payload["value"]?.containerCount, subtree)
    }
    XCTAssertEqual(command(#"{"type":"display","payload":{"value":\#(duplicated[0])}}"#, lazy: .commandPayload)
      .payload["value"]?.containerCount, 1)

    // Same key in sibling or nested objects isn't a duplicate: stays raw.
    let distinct = #"{"pad":"\#(pad)","a":{"a":1,"b":{"a":2}},"b":[{"a":1},{"a":2}],\#(many)}"#
    guard case .raw(let r)? = command(#"{"type":"display","payload":{"value":\#(distinct)}}"#, lazy: .commandPayload)
      .payload["value"]
    else { return XCTFail("distinct keys should stay raw") }
    XCTAssertEqual(r.count, 43)
    XCTAssertTrue(r.isVerbatimJSON)
  }

  func testThresholdBoundary() throws {
    let subtree = #"{"k":"0123456789"}"#  // 18 bytes
    let n = subtree.utf8.count
    let at = JSONParser.parse(envelope(#"{"v":\#(subtree)}"#), lazy: LazyJSONPolicy(minBytes: n))
    let above = JSONParser.parse(envelope(#"{"v":\#(subtree)}"#), lazy: LazyJSONPolicy(minBytes: n + 1))
    guard case .raw(let r)? = at?["payload"]?["v"] else { return XCTFail("at threshold should be raw") }
    XCTAssertEqual(r.bytes.count, n)
    guard case .object? = above?["payload"]?["v"] else { return XCTFail("below threshold should be parsed") }

    // Default policy: a 900-byte body is parsed, a 20 KB one is raw.
    let small = #"{"type":"api.response","payload":{"response":{"body":\#(Self.loadItems(8))}}}"#
    XCTAssertLessThan(Self.loadItems(8).utf8.count, 1024)
    guard case .array? = command(small, lazy: .commandPayload).payload["response"]?["body"]
    else { return XCTFail("small body should be parsed") }
  }

  // MARK: - Lazy == eager

  private static let corpus: [String] = [
    loadFrames[0], loadFrames[1], loadFrames[2], loadFrames[3],
    // Repair triggers deep inside raw subtrees (and one spelled with escapes).
    #"{"type":"log","payload":{"message":{"ctx":{"a":"~~~ null ~~~","b":["~~~ undefined ~~~",{"c":"~~~ hello ~~~"}],"d":"\u007e~~ zero ~~~","e":"~~~ Infinity ~~~"}}}}"#,
    // Pretty-printed (non-canonical) sender, `\/`, uppercase hex, `1.0`, `1E5`, `-0`.
    "{\"type\":\"api.response\",\"payload\":{\"request\":{\"url\":\"https://x.dev/api\",\"data\":{\n  \"path\" : \"\\/users\\/1\",\n  \"n\": [1.0, 1E5, -0, 1e-7],\n  \"s\": \"\\u0041\\u001F\"\n}}}}",
    // Key order spanning search, numbers in JS spelling, unicode.
    #"{"type":"log","payload":{"message":{"nested":{"b":2,"a":1,"x":1e-7,"u":"é 😀 \u001f"}}}}"#,
    #"{"type":"state.values.change","payload":{"changes":[{"path":"user","value":{"name":"alice","password":"hunter2"}}]}}"#,
    #"{"type":"display","payload":{"name":"N","value":[[1,2],{"k":[{"deep":"Bearer abc.def.ghi"}]}],"preview":"p"}}"#,
    #"{"type":"t","payload":"top-level ~~~ null ~~~ string"}"#,
  ]

  func testLazySubtreeParseEqualsEagerParseIncludingRepair() throws {
    for frame in Self.corpus {
      let eager = command(frame, lazy: nil)
      let lazy = command(frame, lazy: maxLazy)
      XCTAssertFalse(containsRaw(eager.payload))
      XCTAssertEqual(lazy.payload, eager.payload, frame)
      XCTAssertEqual(lazy.diff, eager.diff, frame)
      // Same text through the writer (verbatim raw or materialized), in order.
      XCTAssertEqual(JSONWriter.stringify(lazy.payload), JSONWriter.stringify(eager.payload), frame)
      XCTAssertEqual(lazy.payload.prettyString(), eager.payload.prettyString(), frame)
    }
    // On a search path (`payload.message`) the repair-needing subtree is
    // parsed at receive time; off one it stays raw and repairs on demand.
    let searched = command(Self.corpus[4], lazy: maxLazy)
    XCTAssertFalse(containsRaw(searched.payload))
    let offPath = Self.corpus[4].replacingOccurrences(of: #""type":"log","payload":{"message":"#, with: #""type":"display","payload":{"value":"#)
    let repaired = command(offPath, lazy: maxLazy)
    guard case .raw(let value)? = repaired.payload["value"] else { return XCTFail("value not raw") }
    XCTAssertTrue(value.needsRepair)
    let ctx = value.materialize()["ctx"]
    XCTAssertEqual(ctx?["a"], .null)
    XCTAssertEqual(ctx?["b"]?[1]?["c"], .string(" hello "))
    XCTAssertEqual(ctx?["d"], .number(0))
    XCTAssertEqual(ctx, searched.payload["message"]?["ctx"])
  }

  func testMalformedRawSubtreeRejectsWholeMessage() {
    let bad = [
      #"{"type":"t","payload":{"v":{"a":[1,2,],"b":1}}}"#,
      #"{"type":"t","payload":{"v":{"a":01}}}"#,
      #"{"type":"t","payload":{"v":{"a":"\x"}}}"#,
      #"{"type":"t","payload":{"v":{"a" 1}}}"#,
      #"{"type":"t","payload":{"v":[1 2]}}"#,
      #"{"type":"t","payload":{"v":{"a":1}}"#,
    ]
    for frame in bad {
      XCTAssertNil(JSONParser.parse(Data(frame.utf8)), frame)
      XCTAssertNil(JSONParser.parse(Data(frame.utf8), lazy: maxLazy), frame)
    }
  }

  func testDepthLimitAppliesInsideRawSubtrees() {
    // envelope(1) + payload(1) + v's nesting: total 512 is fine, 513 is not.
    func doc(_ inner: Int) -> Data {
      envelope(#"{"v":\#(String(repeating: "[", count: inner))\#(String(repeating: "]", count: inner))}"#)
    }
    XCTAssertNotNil(JSONParser.parse(doc(510), lazy: maxLazy))
    XCTAssertNil(JSONParser.parse(doc(511), lazy: maxLazy))
    XCTAssertNotNil(JSONParser.parse(doc(510)))
    XCTAssertNil(JSONParser.parse(doc(511)))
  }

  // MARK: - Flags

  func testNodeStringifyOutputIsCanonicalAndWrittenVerbatim() throws {
    // Produced by node's JSON.stringify.
    let fixtures = [
      #"{"a":"\u001f\u0000 \#u{2028} é 😀 tab\there","q":"say \"hi\" \\ back/slash","n":[0.1,1e-7,1e+21,-5,123456789012345680000,5e-324,1.5,-0.000001,0.000001,9007199254740992],"e":{},"f":[],"t":true,"z":null}"#,
      #"[{"id":1,"name":"item 1","tags":["a","b"],"nested":{"x":1,"y":"lorem"}},{"zeta":1,"alpha":2,"mid":3}]"#,
    ]
    for text in fixtures {
      let r = try XCTUnwrap(raw(text))
      XCTAssertTrue(r.isCanonical, text)
      XCTAssertFalse(r.needsRepair, text)
      XCTAssertEqual(r.text, text)
      XCTAssertEqual(JSONWriter.stringify(r.materialize()), text)
      let before = materializeCount
      XCTAssertEqual(JSONWriter.stringify(.raw(r)), text)
      XCTAssertEqual(materializeCount, before, "canonical raw must be written without parsing")
    }
  }

  func testNonCanonicalInputsAreRestringified() throws {
    let cases: [(String, String)] = [
      ("{ \"a\": 1 }", #"{"a":1}"#),
      (#"{"a":"\/"}"#, #"{"a":"/"}"#),
      (#"[1.0]"#, #"[1]"#),
      (#"[1E5]"#, #"[100000]"#),
      (#"[1e5]"#, #"[100000]"#),
      (#"[-0]"#, #"[0]"#),
      (#"[0.0000001]"#, #"[1e-7]"#),
      (#"[1e400]"#, #"[null]"#),
      (#"["\u0041"]"#, #"["A"]"#),
      (#"["\u001F"]"#, #"["\u001f"]"#),
      (#"["\u000a"]"#, #"["\n"]"#),
      (#"["\ud83d\ude00"]"#, #"["😀"]"#),
    ]
    for (input, expected) in cases {
      let r = try XCTUnwrap(raw(input))
      XCTAssertFalse(r.isCanonical, input)
      XCTAssertEqual(JSONWriter.stringify(.raw(r)), expected, input)
      XCTAssertEqual(JSONWriter.stringify(.object(["v": .raw(r)])), #"{"v":\#(expected)}"#, input)
    }
  }

  func testInvalidUTF8IsNotCanonical() throws {
    var bytes = Array(#"{"type":"t","payload":{"v":["a"#.utf8)
    bytes.append(0xFF)
    bytes += Array(#""]}}"#.utf8)
    guard case .raw(let r)? = JSONParser.parse(Data(bytes), lazy: maxLazy)?["payload"]?["v"]
    else { return XCTFail("not raw") }
    XCTAssertFalse(r.isCanonical)
    XCTAssertEqual(JSONWriter.stringify(.raw(r)), "[\"a\u{FFFD}\"]")
  }

  func testNeedsRepairFlag() throws {
    XCTAssertTrue(try XCTUnwrap(raw(#"{"x":[{"y":"~~~ null ~~~"}]}"#)).needsRepair)
    XCTAssertTrue(try XCTUnwrap(raw(#"["\u007e~~ null ~~~"]"#)).needsRepair)
    // Keys never trigger repair; `~~~` not at the start of a value neither.
    XCTAssertFalse(try XCTUnwrap(raw(#"{"~~~ null ~~~":"a ~~~ null ~~~"}"#)).needsRepair)
    let r = try XCTUnwrap(raw(#"{"x":[{"y":"~~~ null ~~~"}]}"#))
    XCTAssertEqual(r.materialize()["x"]?[0]?["y"], .null)
    XCTAssertEqual(JSONWriter.stringify(.raw(r)), #"{"x":[{"y":null}]}"#)
  }

  func testAccessorsAndHelpersOnRaw() throws {
    let obj = try XCTUnwrap(raw(#"{"a":[1,2,3],"b":{"c":true}}"#))
    let arr = try XCTUnwrap(raw(#"[1,[2],{"x":3}]"#))
    let before = materializeCount
    XCTAssertTrue(JSONValue.raw(obj).isObject)
    XCTAssertFalse(JSONValue.raw(obj).isArray)
    XCTAssertTrue(JSONValue.raw(arr).isArray)
    XCTAssertEqual(JSONValue.raw(obj).containerCount, 2)
    XCTAssertEqual(JSONValue.raw(arr).containerCount, 3)
    XCTAssertTrue(JSONValue.raw(obj).isTruthy)
    XCTAssertTrue(JSONValue.raw(arr).isObjectOrArray)
    XCTAssertNil(JSONValue.raw(arr).stringValue)
    XCTAssertEqual(treePreview(.raw(arr)), "3 items")
    XCTAssertEqual(materializeCount, before, "zero-parse helpers must not materialize")

    XCTAssertEqual(JSONValue.raw(obj)["b"]?["c"], .bool(true))
    XCTAssertEqual(JSONValue.raw(arr)[2]?["x"], .number(3))
    XCTAssertNil(JSONValue.raw(arr).objectValue)
    XCTAssertNil(JSONValue.raw(obj).arrayValue)
    XCTAssertEqual(treePreview(.raw(obj)), treePreview(obj.materialize()))
    XCTAssertEqual(JSONValue.raw(obj), .object(["b": .object(["c": .bool(true)]), "a": .array([1, 2, 3].map { .number($0) })]))
    XCTAssertNotEqual(JSONValue.raw(obj), .raw(arr))
    XCTAssertEqual(JSONValue.raw(obj).materialized, obj.materialize())
  }

  // MARK: - filterSearch

  func testFilterSearchMatchesInsideLazySubtreesExactlyAsEager() {
    let eager = Self.corpus.enumerated().map { command($1, lazy: nil, id: $0) }
    let lazy = Self.corpus.enumerated().map { command($1, lazy: maxLazy, id: $0) }
    XCTAssertTrue(lazy.contains { containsRaw($0.payload) })
    let terms = [
      #""b":2,"a""#, #""a":1,"b""#, "1e-7", "/users/1", #"\/users"#, "\"path\":\"/users", "\"n\":[1,100000,0",
      "hello", " hello ", "~~~", "null", #""a":null"#, "\"A", "A\\u001f", "\\u001f", "é 😀", "item 199",
      "lorem ipsum", "zero", ":0", "nested", "{\"ctx\"", "password", "Bearer", "1.0", "1E5", "deep", "x.dev",
      "\"s\":\"A", "{\"x\":1e-7", "\"tags\":[\"a\",\"b\"]",
    ]
    for term in terms {
      XCTAssertEqual(
        filterSearch(lazy, search: term).map(\.messageId), filterSearch(eager, search: term).map(\.messageId),
        "search \(term)")
    }
    // Sanity: the terms do hit inside raw subtrees.
    XCTAssertEqual(filterSearch(lazy, search: #""b":2,"a""#).map(\.messageId), [6])
    XCTAssertEqual(filterSearch(lazy, search: "/users/1").map(\.messageId), [5])
    XCTAssertEqual(filterSearch(lazy, search: "hello").map(\.messageId), [4])
  }

  // MARK: - Hot paths never parse

  func testRowModelsAndSearchDoNotMaterializeLoadShapedCommands() {
    var frames = Self.loadFrames
    // An api.response whose (canonical) request.data is big enough to be raw.
    frames.append(#"{"type":"api.response","payload":{"request":{"url":"https://e.com/g","method":"POST","data":\#(Self.loadBody)},"response":{"status":200,"body":\#(Self.loadBody)}}}"#)
    let commands = frames.enumerated().map { command($1, lazy: .commandPayload, id: $0) }
    guard case .raw? = commands[4].payload["request"]?["data"] else { return XCTFail("request.data not raw") }
    let before = materializeCount
    for c in commands { _ = TimelineRowModel.resolve(c) }
    _ = filterSearch(commands, search: "no such text anywhere")
    XCTAssertEqual(filterSearch(commands, search: "item 199").map(\.messageId), [4])
    XCTAssertEqual(materializeCount, before)
  }

  // MARK: - Redaction / MCP

  func testRedactionMaterializesAndRedactsRawSubtrees() throws {
    let frame = #"{"type":"display","payload":{"value":{"user":{"name":"alice","password":"hunter2","token":"t0k"},"auth":"Bearer abc.def.ghi","list":[{"apiKey":"k"}]}}}"#
    let lazy = command(frame, lazy: maxLazy)
    guard case .raw? = lazy.payload["value"] else { return XCTFail("value not raw") }
    let out = Redaction.redact(lazy.payload, rules: .defaults)
    XCTAssertFalse(containsRaw(out))
    let text = JSONWriter.stringify(out)
    XCTAssertFalse(text.contains("hunter2"), text)
    XCTAssertFalse(text.contains("t0k"), text)
    XCTAssertFalse(text.contains("abc.def.ghi"), text)
    XCTAssertEqual(out, Redaction.redact(command(frame, lazy: nil).payload, rules: .defaults))
    XCTAssertEqual(text, JSONWriter.stringify(Redaction.redact(command(frame, lazy: nil).payload, rules: .defaults)))
  }

  func testMcpOutputIsIdenticalForLazyAndEagerCommands() throws {
    func responses(lazy: LazyJSONPolicy?) -> [String] {
      let core = McpCore()
      core.setBuffering(true)
      var frames = Self.corpus
      frames.append(#"{"type":"api.response","payload":{"request":{"url":"https://e.com/login","method":"POST","data":{"password":"hunter2","pad":"\#(String(repeating: "x", count: 2000))"}},"response":{"status":200,"body":{"token":"secret-token","items":\#(Self.loadItems(30))}}}}"#)
      for (i, f) in frames.enumerated() { core.buffer(command(f, lazy: lazy, id: i + 1)) }
      return ["reactotron://timeline", "reactotron://timeline/api.response", "reactotron://timeline/log",
        "reactotron://timeline/display", "reactotron://network/log"].map { uri in
        let body = #"{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"\#(uri)"}}"#
        let (_, _, data) = core.handle(method: "POST", path: "/mcp", headers: [:], body: Data(body.utf8))
        return String(decoding: data, as: UTF8.self)
      }
    }
    let eager = responses(lazy: nil)
    let lazy = responses(lazy: maxLazy)
    XCTAssertEqual(lazy, eager)
    // Full payloads (timeline_by_type) are redacted after materializing.
    // (`network/log` isn't checked: it truncates bodies to 500 chars before
    // redaction, eager or lazy alike, so a cut-off JSON string isn't
    // re-parsed — pre-existing behavior this test only pins as unchanged.)
    for text in lazy[0...3] {
      XCTAssertFalse(text.contains("hunter2"), text)
      XCTAssertFalse(text.contains("secret-token"), text)
    }
    XCTAssertTrue(lazy[1].contains("item 29"), "full api.response payload expected")
  }
}

/// End-to-end over a real socket with the server's own lazy policy.
final class RawJSONServerTests: XCTestCase {
  private var server: ReactotronServer!
  private var port: UInt16!

  override func setUp() {
    server = ReactotronServer()
    port = UInt16.random(in: 20_000...40_000)
  }
  override func tearDown() { server.stop() }

  private final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
  }

  func testLargeCommandArrivesRawAndReplaysVerbatim() async throws {
    await withCheckedContinuation { cont in
      server.events.started = { cont.resume() }
      server.start(port: port)
    }
    let actionText = #"{"type":"SOME_ACTION","payload":[\#((0..<40).map { #"{"id":\#($0),"name":"item \#($0)","url":"a/b"}"# }.joined(separator: ","))]}"#
    let got = expectation(description: "commands")
    got.expectedFulfillmentCount = 2
    let received = Box<[Command]>([])
    server.events.command = { cmd in
      guard cmd.type != "client.intro" else { return }
      received.value.append(cmd)
      got.fulfill()
    }
    let client = TestClient(port: port)
    try await client.send(#"{"type":"client.intro","payload":{"clientId":"lazy"}}"#)
    try await client.send(#"{"type":"state.action.complete","payload":{"name":"SOME_ACTION","action":\#(actionText),"ms":1}}"#)
    try await client.send(#"{"type":"state.backup.response","payload":{"state":{"big":"\#(String(repeating: "s", count: 1500))","n":[1,2]}}}"#)
    await fulfillment(of: [got], timeout: 5)

    let action = try XCTUnwrap(received.value.first { $0.type == "state.action.complete" }?.payload["action"])
    guard case .raw(let r) = action else { return XCTFail("action should be raw") }
    XCTAssertEqual(r.text, actionText)
    XCTAssertEqual(action["payload"]?[39]?["name"], .string("item 39"))

    let backup = try XCTUnwrap(received.value.first { $0.type == "state.backup.response" })
    guard case .raw? = backup.payload["state"] else { return XCTFail("state should be raw") }
    XCTAssertEqual(backup.payload.objectValue?.keys, ["state", "name"])  // server-added `name`

    // Replay the action and restore the snapshot: the raw bytes go out verbatim.
    server.send(type: "state.action.dispatch", payload: .object(["action": action]), clientId: "lazy")
    var msg = try await client.receive()
    while !msg.contains("state.action.dispatch") { msg = try await client.receive() }
    XCTAssertEqual(msg, #"{"type":"state.action.dispatch","payload":{"action":\#(actionText)}}"#)

    server.send(type: "state.restore.request", payload: .object(["state": backup.payload["state"]!]), clientId: "lazy")
    msg = try await client.receive()
    while !msg.contains("state.restore.request") { msg = try await client.receive() }
    XCTAssertEqual(
      JSONValue.parse(Data(msg.utf8))?["payload"]?["state"],
      .object(["big": .string(String(repeating: "s", count: 1500)), "n": .array([.number(1), .number(2)])]))
    client.close()
  }
}
