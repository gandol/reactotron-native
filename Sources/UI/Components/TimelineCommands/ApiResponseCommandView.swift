import SwiftUI

/// The 5 possible tabs from `ApiResponseCommand/index.tsx`'s `Tab` enum.
/// Request Body / Request Params are conditional on the request actually
/// carrying `data`/`params` (`!!request.data && ...`), matching source.
private enum ApiTab: Equatable {
  case responseBody, responseHeaders, requestBody, requestParams, requestHeaders
}

/// Port of `ApiResponseCommand/index.tsx`.
///
/// Scope note: source's toolbar has 4 buttons (copy response, copy request,
/// copy-as-markdown via `apiToMarkdown`, copy-as-cURL via
/// `apiRequestToCurl`). This ports the "copy response" button — the other 3
/// depend on porting two more nontrivial formatting utilities
/// (`utils/api-to-markdown`, `utils/api-to-curl`) not otherwise used
/// anywhere else in this task; deferred as a documented scope cut rather
/// than ported for completeness's sake.
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
      toolbar: [
        TimelineToolbarAction(icon: .mdContentCopy, tip: "Copy JSON response to clipboard") {
          copyToClipboard(prettyJSON(response?["body"] ?? .null))
        }
      ]
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
    if let value, !value.isNull {
      TreeView(value: jsonAwareValue(value))
    } else {
      Text("null").font(Theme.font(12)).foregroundStyle(Theme.tag)
    }
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
