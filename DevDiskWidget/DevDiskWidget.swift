import WidgetKit
import SwiftUI

struct DiskEntry: TimelineEntry {
    let date: Date
    let result: ScanResult
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DiskEntry {
        DiskEntry(date: Date(), result: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (DiskEntry) -> Void) {
        completion(DiskEntry(date: Date(), result: SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskEntry>) -> Void) {
        // The widget only reads the snapshot the menu bar app already wrote
        // (fast — no subprocess calls here, which WidgetKit would budget-kill).
        let entry = DiskEntry(date: Date(), result: SharedStore.load())
        // Re-check every 15 min in case the app updated the file meanwhile.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct DevDiskWidgetView: View {
    var entry: DiskEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let result = entry.result
        VStack(alignment: .leading, spacing: 6) {
            if result.scannedAt == Date.distantPast {
                emptyState
            } else {
                header(result)
                progressBar(result)
                if family != .systemSmall {
                    topTargets(result)
                }
                Spacer(minLength: 0)
                Text("Updated \(result.scannedAt, style: .relative) ago")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(for: .widget) { Color(.windowBackgroundColor) }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "internaldrive")
                .font(.title2)
            Text("Open DevDiskApp once")
                .font(.system(size: 12, weight: .semibold))
            Text("to run the first scan.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func header(_ result: ScanResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(humanBytes(result.disk.freeBytes))
                    .font(.system(size: 20, weight: .bold))
                Text("free")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(Int(result.disk.percentUsed))%")
                    .font(.system(size: 14, weight: .semibold))
                Text("used")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func progressBar(_ result: ScanResult) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.25))
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * CGFloat(result.disk.percentUsed / 100))
            }
        }
        .frame(height: 6)
    }

    private func topTargets(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(result.topTargets.prefix(family == .systemLarge ? 6 : 3)) { target in
                HStack {
                    Circle()
                        .fill(riskColor(target.risk))
                        .frame(width: 6, height: 6)
                    Text(target.label)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Text(humanBytes(target.bytes))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 4)
    }

    private func riskColor(_ risk: String) -> Color {
        switch risk {
        case "safe": return .green
        case "caution": return .yellow
        default: return .red
        }
    }
}

struct DevDiskWidget: Widget {
    let kind = "DevDiskWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DevDiskWidgetView(entry: entry)
        }
        .configurationDisplayName("Dev Disk Cleanup")
        .description("Disk usage & top reclaimable dev caches.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    DevDiskWidget()
} timeline: {
    DiskEntry(date: .now, result: .empty)
}
