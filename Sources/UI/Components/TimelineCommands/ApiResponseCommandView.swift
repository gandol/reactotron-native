import SwiftUI

/// The 5 possible tabs from `ApiResponseCommand/index.tsx`'s `Tab` enum.
/// Request Body / Request Params are conditional on the request actually
/// carrying `data`/`params` (`!!request.data && ...`), matching source.
private enum ApiTab: Equatable {
  case responseBody, responseHeaders, requestBody, requestParams, requestHeaders
}

/// Port of `ApiResponseCommand/index.tsx`, including the full 4-button copy
/// toolbar from `buildToolbar`: Copy JSON response, Copy JSON request (only
/// when the request carries a body), Copy as markdown (`apiToMarkdown`), and
/// Copy as cURL (`apiRequestToCurl`).
struct ApiResponseCommandView: View {
  let command: Command
  @State private var activeTab: ApiTab?

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let payload = command.payload
    let request = payload["request"]
    let response = payload["response"]
    let statusCode = response?["status"]?.numberValue.map { Int($0) }
    let duration = payload["duration"]?.numberValue.map { Int($0) }
    let hasRequestBody = request?["data"]?.isTruthy == true
    let hasRequestParams = request?["params"]?.isTruthy == true

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important,
      responseStatusCode: statusCode,
      toolbar: apiToolbar(payload: payload, request: request, response: response, hasRequestBody: hasRequestBody)
    ) {
      VStack(alignment: .leading, spacing: 10) {
        Text(request?["url"]?.stringValue ?? "")
          .font(Theme.font(12))
          .foregroundStyle(Theme.bold)
          .textSelection(.enabled)

        KeyValueTable(object: [
          "Status Code": statusCode.map { JSONValue.number(Double($0)) } ?? .null,
          "Method": request?["method"] ?? .string(""),
          "Duration (ms)": duration.map { JSONValue.number(Double($0)) } ?? .null,
        ])

        HStack(spacing: 6) {
          tabButton("Response", .responseBody)
          tabButton("Response Headers", .responseHeaders)
          if hasRequestBody { tabButton("Request", .requestBody) }
          if hasRequestParams { tabButton("Request Params", .requestParams) }
          tabButton("Request Headers", .requestHeaders)
        }

        tabContent(request: request, response: response)
      }
    }
  }

  /// Port of `buildToolbar` — the 4 copy actions, in source order, with the
  /// request-copy button present only when the request carries a body.
  private func apiToolbar(payload: JSONValue, request: JSONValue?, response: JSONValue?, hasRequestBody: Bool) -> [TimelineToolbarAction] {
    var items: [TimelineToolbarAction] = []

    // Copy JSON response
    items.append(TimelineToolbarAction(icon: .mdCallReceived, tip: "Copy JSON response to clipboard") {
      copyToClipboard(prettyJSON(response?["body"] ?? .null))
    })

    // Copy JSON request (only when request has a body)
    if hasRequestBody {
      items.append(TimelineToolbarAction(icon: .mdCallMade, tip: "Copy JSON request to clipboard") {
        let data = request?["data"] ?? .null
        // If it's a JSON string, re-pretty-print it; else copy raw.
        if let s = data.stringValue, let reparsed = JSONValue.parse(Data(s.utf8)) {
          copyToClipboard(prettyJSON(reparsed))
        } else if let s = data.stringValue {
          copyToClipboard(s)
        } else {
          copyToClipboard(prettyJSON(data))
        }
      })
    }

    // Copy as markdown
    items.append(TimelineToolbarAction(icon: .mdReceipt, tip: "Copy as markdown to clipboard") {
      copyToClipboard(apiToMarkdown(payload))
    })

    // Copy as cURL
    items.append(TimelineToolbarAction(icon: .mdContentCopy, tip: "Copy JSON request as cURL") {
      copyToClipboard(apiRequestToCurl(payload))
    })

    return items
  }

  @ViewBuilder
  private func tabContent(request: JSONValue?, response: JSONValue?) -> some View {
    switch activeTab {
    case .responseBody: apiValueView(response?["body"])
    case .responseHeaders: apiValueView(response?["headers"])
    case .requestBody: apiValueView(request?["data"])
    case .requestParams: apiValueView(request?["params"])
    case .requestHeaders: apiValueView(request?["headers"])
    case nil: EmptyView()
    }
  }

  @ViewBuilder
  private func apiValueView(_ value: JSONValue?) -> some View {
    // ContentValueView matches the real app: shallow objects (like HTTP
    // headers) become a two-column table, nested data becomes a tree, strings
    // become selectable text.
    ContentValueView(value: value ?? .null)
  }

  private func tabButton(_ text: String, _ tab: ApiTab) -> some View {
    let isActive = activeTab == tab
    return Button {
      activeTab = isActive ? nil : tab
    } label: {
      Text(text)
        .font(Theme.font(11))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 3).fill(isActive ? Theme.constant : Theme.backgroundLighter))
        .foregroundStyle(isActive ? Theme.background : Theme.foreground)
    }
    .buttonStyle(.plain)
  }
}
