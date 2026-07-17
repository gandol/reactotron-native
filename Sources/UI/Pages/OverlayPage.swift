import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Port of `pages/reactNative/Overlay.tsx` + its `components/` (`OverlayAlignment`,
/// `OverlayButton`, `OverlayLayoutType`, `OverlayMargins`, `OverlayOpacity`,
/// `OverlayResizeMode`, `OverlayScale`, `Shared`).
///
/// `overlayParams` is local view state — a `[String: JSONValue]` bag mirroring
/// the source's `useOverlay()` hook's `useState<OverlayParams>({})`: it starts
/// empty and each control's `onChange` merges its partial update into the
/// accumulated object, then sends the WHOLE merged object as the `"overlay"`
/// command payload (verified against `useOverlay.ts`'s `updateOverlayParams`:
/// `{...overlayParams, ...params}` sent wholesale, not just the diff). Because
/// it's local `@State` rather than something owned by `AppModel`/`SessionStore`,
/// it resets if this page's view identity resets (e.g. navigating to another
/// page and back) — the source's equivalent state lives in a
/// `ReactNativeProvider` mounted above the router, so it technically persists
/// across navigation in Electron. Out of scope to replicate here per the task
/// brief (interface only asks for the page + the wire commands it sends).
///
/// Not ported: the source's "resend current overlay to a client that just
/// connected" behavior (`useOverlay.ts` listens for `client.intro` and
/// re-sends `overlayParams` addressed at that specific new client via
/// `sendCommand(type, payload, clientId)`). `AppModel.sendCommand` only
/// targets the currently *selected* client (no arbitrary-clientId addressing
/// exists in this port's server API), so there's no equivalent hook to wire.
///
/// Image import: the source's `DropZone` reads a dropped file via Electron's
/// `fs.readFile` + `nativeImage.createFromBuffer(...).toDataURL()`. This port
/// uses `.onDrop(of: [.fileURL])` + `NSBitmapImageRep` to reproduce the same
/// outcome — a `data:image/png;base64,...` URI and the image's raw pixel
/// dimensions — since there's no Electron `nativeImage` equivalent here.
struct OverlayPage: View {
  @Environment(AppModel.self) private var model

  @State private var overlayParams: [String: JSONValue] = [:]
  @State private var localURI: String?
  @State private var originalWidth = 0
  @State private var originalHeight = 0
  @State private var layoutType: OverlayLayout = .image
  @State private var scale: Double = 1
  @State private var isTargeted = false

  private var uri: JSONValue? { overlayParams["uri"] }
  private var hasImage: Bool { uri?.isTruthy ?? false }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(tabs: reactNativeHeaderTabs(model: model, active: .nativeOverlay))

      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          titleRow

          dropZone
          if hasImage {
            reapplyRow
          }

          if hasImage { layoutSection }
          if hasImage, layoutType == .image { scaleSection }
          if hasImage, layoutType == .screen { resizeModeSection }
          if hasImage, layoutType == .image { alignmentSection }
          if hasImage { opacitySection }
          if hasImage { marginsSection }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
      }
    }
  }

  // MARK: - Title + debug toggle

  private var titleRow: some View {
    HStack {
      Text("Image Overlay")
        .font(Theme.font(24))
        .foregroundStyle(Theme.tag)
        .padding(.top, 20)

      Spacer()

      #if DEBUG
      debugToggleRow
      #endif
    }
  }

  #if DEBUG
  private var debugToggleRow: some View {
    HStack(spacing: 0) {
      Text("Debug View").foregroundStyle(Theme.foregroundDark)
      overlayButton("On", selected: overlayParams["showDebug"]?.boolValue == true) {
        updateOverlayParams(["showDebug": .bool(true)])
      }
      overlayButton("Off", selected: overlayParams["showDebug"]?.boolValue != true) {
        updateOverlayParams(["showDebug": .bool(false)])
      }
    }
    .padding(.top, 20)
  }
  #endif

  // MARK: - Drop zone

  private var dropZone: some View {
    ZStack {
      Rectangle()
        .fill(Theme.subtleLine)
        .overlay(Rectangle().stroke(Theme.backgroundSubtleDark, lineWidth: 1))

      if let localURI, let nsImage = Self.decodeDataURI(localURI) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .padding(4)
          .onTapGesture { removeImage() }
      } else {
        Text("Drop Image Here").foregroundStyle(Theme.foregroundLight)
      }
    }
    .frame(width: 200, height: 200)
    .padding(.top, 10)
    .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
      handleDrop(providers)
    }
  }

  private var reapplyRow: some View {
    HStack {
      overlayButton("Reapply Overlay", selected: false, action: applyOverlay)
    }
    .padding(.top, 10)
  }

  // MARK: - Layout

  private var layoutSection: some View {
    section("Layout") {
      HStack(spacing: 0) {
        overlayButton("Image", selected: layoutType == .image) { handleLayoutChange(.image) }
        overlayButton("Screen", selected: layoutType == .screen) { handleLayoutChange(.screen) }
      }
    }
  }

  // MARK: - Scale

  private static let scaleOptions: [(title: String, value: Double)] =
    [("1/3", 0.33), ("1/2", 0.5), ("1", 1), ("2", 2), ("3", 3)]

  private var scaleSection: some View {
    section("Scale") {
      HStack(spacing: 0) {
        ForEach(Self.scaleOptions, id: \.title) { option in
          overlayButton(option.title, selected: scale == option.value) { handleScaleChange(option.value) }
        }
      }
    }
  }

  // MARK: - Resize mode

  private static let resizeModes: [(title: String, value: String)] =
    [("Stretch", "stretch"), ("Cover", "cover"), ("Contain", "contain")]

  private var resizeModeSection: some View {
    section("Resize Mode") {
      HStack(spacing: 0) {
        ForEach(Self.resizeModes, id: \.value) { mode in
          overlayButton(mode.title, selected: overlayParams["resizeMode"]?.stringValue == mode.value) {
            handleResizeChange(mode.value)
          }
        }
      }
    }
  }

  // MARK: - Alignment

  private static let justifyOptions = ["flex-start", "center", "flex-end"]
  private static let alignOptions = ["flex-start", "center", "flex-end"]

  private var alignmentSection: some View {
    section("Alignment") {
      VStack(spacing: 0) {
        ForEach(Self.justifyOptions, id: \.self) { justify in
          HStack(spacing: 0) {
            ForEach(Self.alignOptions, id: \.self) { align in
              let selected = overlayParams["justifyContent"]?.stringValue == justify
                && overlayParams["alignItems"]?.stringValue == align
              Button {
                handleAlignmentChanged(justify, align)
              } label: {
                RoundedRectangle(cornerRadius: 2)
                  .fill(selected ? Theme.bold : Theme.subtleLine)
                  .frame(width: 32, height: 32)
                  .overlay(RoundedRectangle(cornerRadius: 2).stroke(selected ? Theme.bold : Theme.subtleLine))
              }
              .buttonStyle(.plain)
              .padding(3)
            }
          }
        }
      }
    }
  }

  // MARK: - Opacity

  private static let opacityOptions: [Double] = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1]

  private var opacitySection: some View {
    section("Opacity") {
      HStack(spacing: 0) {
        ForEach(Self.opacityOptions, id: \.self) { value in
          overlayButton(Self.opacityTitle(value), selected: overlayParams["opacity"]?.numberValue == value) {
            handleOpacityChange(value)
          }
        }
      }
    }
  }

  private static func opacityTitle(_ value: Double) -> String {
    value == 0 ? "0" : value == 1 ? "1" : String(value)
  }

  // MARK: - Margins

  private var marginsSection: some View {
    section("Margins") {
      HStack(spacing: 4) {
        marginField("Top", key: "marginTop")
        marginField("Right", key: "marginRight")
        marginField("Bottom", key: "marginBottom")
        marginField("Left", key: "marginLeft")
      }
    }
  }

  private func marginField(_ label: String, key: String) -> some View {
    HStack(spacing: 4) {
      Text(label).foregroundStyle(Theme.foregroundDark)
      TextField(
        "",
        text: Binding(
          get: { Self.marginText(overlayParams[key]) },
          set: { handleMarginChange(key, $0) }
        )
      )
      .textFieldStyle(.plain)
      .frame(width: 45)
      .padding(6)
      .background(Theme.backgroundLight)
      .foregroundStyle(Color.black)
    }
  }

  private static func marginText(_ value: JSONValue?) -> String {
    guard let n = value?.numberValue else { return "0" }
    return n.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(n)) : String(n)
  }

  // MARK: - Shared bits

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title).foregroundStyle(Theme.tag)
      content()
    }
    .padding(.top, 20)
  }

  private func overlayButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(Theme.font(13))
        .foregroundStyle(selected ? Theme.bold : Theme.foregroundDark)
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Theme.subtleLine)
        .overlay(Rectangle().stroke(Theme.backgroundSubtleDark, lineWidth: 1))
    }
    .buttonStyle(.plain)
    .padding(.trailing, 4)
  }

  // MARK: - Port of Overlay.tsx's handlers

  /// Port of `updateOverlayParams`: merges `partial` into the accumulated
  /// state, then sends the WHOLE merged object as the command payload.
  private func updateOverlayParams(_ partial: [String: JSONValue]) {
    for (key, value) in partial { overlayParams[key] = value }
    model.sendCommand(type: "overlay", payload: .object(overlayParams))
  }

  /// Port of `importFile`.
  private func importFile(_ url: URL) {
    guard let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data),
      let png = rep.representation(using: .png, properties: [:])
    else { return }
    let dataURI = "data:image/png;base64,\(png.base64EncodedString())"
    localURI = dataURI
    originalWidth = rep.pixelsWide
    originalHeight = rep.pixelsHigh
    updateOverlayParams([
      "uri": .string(dataURI),
      "width": .number(Double(rep.pixelsWide)),
      "height": .number(Double(rep.pixelsHigh)),
      "opacity": .number(0.5),
      "marginTop": .number(0), "marginRight": .number(0),
      "marginBottom": .number(0), "marginLeft": .number(0),
      "growToWindow": .bool(false),
      "justifyContent": .string("center"), "alignItems": .string("center"),
    ])
  }

  /// Port of `applyOverlay` ("Reapply Overlay" button).
  private func applyOverlay() {
    scale = 1
    updateOverlayParams([
      "uri": localURI.map { .string($0) } ?? .null,
      "width": .number(Double(originalWidth)),
      "height": .number(Double(originalHeight)),
      "opacity": .number(0.5),
      "marginTop": .number(0), "marginRight": .number(0),
      "marginBottom": .number(0), "marginLeft": .number(0),
      "growToWindow": .bool(false),
      "justifyContent": .string("center"), "alignItems": .string("center"),
    ])
  }

  /// Port of `removeImage` (clicking the dropped preview image).
  private func removeImage() {
    localURI = nil
    originalWidth = 0
    originalHeight = 0
    scale = 1
    layoutType = .image
    updateOverlayParams([
      "uri": .null, "width": .null, "height": .null,
      "alignItems": .string("center"), "justifyContent": .string("center"),
    ])
  }

  /// Port of `handleLayoutChange`.
  private func handleLayoutChange(_ newLayoutType: OverlayLayout) {
    let growToWindow = newLayoutType == .screen
    let currentResizeMode = overlayParams["resizeMode"]?.stringValue
    layoutType = newLayoutType
    var partial: [String: JSONValue] = [
      "growToWindow": .bool(growToWindow),
      "width": .number(growToWindow ? Double(originalWidth) : Double(originalWidth) * scale),
      "height": .number(growToWindow ? Double(originalHeight) : Double(originalHeight) * scale),
    ]
    if let resizeMode = growToWindow ? "stretch" : currentResizeMode {
      partial["resizeMode"] = .string(resizeMode)
    }
    updateOverlayParams(partial)
  }

  /// Port of `handleScaleChange`.
  private func handleScaleChange(_ newScale: Double) {
    scale = newScale
    if originalWidth != 0, originalHeight != 0 {
      updateOverlayParams([
        "width": .number(Double(originalWidth) * newScale),
        "height": .number(Double(originalHeight) * newScale),
      ])
    }
  }

  /// Port of `handleResizeChange`.
  private func handleResizeChange(_ newResizeMode: String) {
    guard let width = overlayParams["width"], width.isTruthy,
      let height = overlayParams["height"], height.isTruthy
    else { return }
    updateOverlayParams([
      "resizeMode": .string(newResizeMode),
      "growToWindow": .bool(layoutType == .screen),
      "width": width,
      "height": height,
    ])
  }

  /// Port of `handleAlignmentChanged`.
  private func handleAlignmentChanged(_ justifyContent: String, _ alignItems: String) {
    updateOverlayParams(["justifyContent": .string(justifyContent), "alignItems": .string(alignItems)])
  }

  /// Port of `handleOpacityChange`.
  private func handleOpacityChange(_ newOpacity: Double) {
    let opacity = overlayParams["opacity"]?.numberValue
    if newOpacity == opacity { return }
    if let uri = overlayParams["uri"], uri.isTruthy {
      updateOverlayParams(["opacity": .number(newOpacity)])
    }
  }

  /// Port of `handleMarginChange`. `Number(value || 0)`, NaN falls back to 0.
  private func handleMarginChange(_ key: String, _ text: String) {
    let value = Double(text) ?? 0
    updateOverlayParams([key: .number(value.isNaN ? 0 : value)])
  }

  // MARK: - Drop handling

  private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
    guard let provider = providers.first, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
      return false
    }
    provider.loadDataRepresentation(for: .fileURL) { data, _ in
      guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
      Task { @MainActor in importFile(url) }
    }
    return true
  }

  private static func decodeDataURI(_ uri: String) -> NSImage? {
    guard let commaIdx = uri.firstIndex(of: ","),
      let data = Data(base64Encoded: String(uri[uri.index(after: commaIdx)...]))
    else { return nil }
    return NSImage(data: data)
  }
}

/// Port of `components/OverlayLayoutType.tsx`'s `Layout` enum.
enum OverlayLayout: String {
  case image = "Image"
  case screen = "Screen"
}

// MARK: - Shared React Native tab header

/// Port of the tab row repeated verbatim by both `Overlay.tsx` and
/// `Storybook.tsx` — navigates between the two React Native pages.
@MainActor
func reactNativeHeaderTabs(model: AppModel, active: Page) -> [HeaderTab] {
  [
    (
      text: "Image Overlay", icon: .mdCamera, isActive: active == .nativeOverlay,
      onTap: { model.currentPage = .nativeOverlay }
    ),
    (
      text: "Storybook", icon: .mdBook, isActive: active == .nativeStorybook,
      onTap: { model.currentPage = .nativeStorybook }
    ),
  ]
}
