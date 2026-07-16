import SwiftUI

/// Port of `BenchmarkReportCommand/index.tsx`. No toolbar in source. Skips
/// the first step (source: `if (idx === 0) return null` — the first step is
/// the start marker with zero delta, nothing to show).
struct BenchmarkReportCommandView: View {
  let command: Command

  var body: some View {
    let model = TimelineRowModel.resolve(command)
    let obj = command.payload.objectValue
    let title = obj?["title"]?.stringValue ?? "Benchmark"
    let steps = obj?["steps"]?.arrayValue ?? []
    let totalDuration = steps.last?["time"]?.numberValue ?? 0

    BaseCommandView(
      title: model.title,
      date: command.date,
      preview: model.preview,
      important: command.important
    ) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(Theme.font(12))
          .foregroundStyle(Theme.bold)
          .padding(.bottom, 6)

        ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
          if idx > 0 {
            stepRow(step, totalDuration: totalDuration)
          }
        }
      }
    }
  }

  private func stepRow(_ step: JSONValue, totalDuration: Double) -> some View {
    let time = step["time"]?.numberValue ?? 0
    let delta = step["delta"]?.numberValue ?? 0
    let stepTitle = step["title"]?.stringValue ?? ""
    let startFraction = totalDuration > 0 ? max(0, min(1, (time - delta) / totalDuration)) : 0
    let endFraction = totalDuration > 0 ? max(0, min(1, time / totalDuration)) : 0

    return GeometryReader { geo in
      ZStack(alignment: .leading) {
        Rectangle()
          .fill(Theme.backgroundLighter)
          .frame(width: max(0, CGFloat(endFraction - startFraction)) * geo.size.width)
          .offset(x: CGFloat(startFraction) * geo.size.width)
        HStack {
          Text(stepTitle).foregroundStyle(Theme.foreground)
          Spacer()
          Text(String(format: "%.3fs", delta / 1000)).foregroundStyle(Theme.foreground)
        }
        .padding(.horizontal, 4)
      }
    }
    .frame(height: 22)
    .font(Theme.font(12))
  }
}
