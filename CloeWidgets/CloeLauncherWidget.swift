import SwiftUI
import WidgetKit

/// Static quick-launch widget for the Home Screen and Lock Screen. No live data — it
/// just opens Cloe (or, on the mic affordance, starts hands-free voice) via `cloe://`
/// deep links, so it needs no App Group or timeline reloads.
struct CloeLauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CloeLauncher", provider: CloeLauncherProvider()) { _ in
            CloeLauncherView()
        }
        .configurationDisplayName("Cloe")
        .description("Open Cloe, or tap the mic to talk.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

struct CloeLauncherEntry: TimelineEntry { let date: Date }

/// One static entry, never reloaded — the widget is a launcher, not a data display.
struct CloeLauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> CloeLauncherEntry { CloeLauncherEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (CloeLauncherEntry) -> Void) {
        completion(CloeLauncherEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CloeLauncherEntry>) -> Void) {
        completion(Timeline(entries: [CloeLauncherEntry(date: Date())], policy: .never))
    }
}

struct CloeLauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            // Required by WidgetKit on iOS 17+ for EVERY family (incl. Lock Screen
            // accessories) — without it the widget renders "Please adopt
            // containerBackground API". Accessories get a clear background.
            .containerBackground(for: .widget) {
                switch family {
                case .systemSmall, .systemMedium: Rectangle().fill(.fill.tertiary)
                default: Color.clear
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemMedium: medium
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        default: small
        }
    }

    // MARK: - Home Screen

    // Small widget is a single tap target → whole-widget `widgetURL`, no inner Links.
    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sparkles")
                .font(.title)
                .foregroundStyle(.tint)
            Spacer()
            Text("Ask Cloe").font(.headline)
            Text("Tap to chat").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(CloeDeepLink.chat)
    }

    // Medium can host multiple tap regions → row opens chat, mic starts voice.
    private var medium: some View {
        HStack(spacing: 12) {
            Link(destination: CloeDeepLink.chat) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title)
                        .foregroundStyle(.tint)
                        .frame(width: 52, height: 52)
                        .background(.tint.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ask Cloe").font(.headline)
                        Text("Open the chat").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            Link(destination: CloeDeepLink.voice) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 56, height: 56)
                    .background(.tint.opacity(0.15), in: Circle())
            }
        }
    }

    // MARK: - Lock Screen accessories

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill").font(.title2)
        }
        .widgetURL(CloeDeepLink.voice)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text("Cloe").font(.headline)
                Text("Tap to ask").font(.caption2)
            }
            Spacer(minLength: 0)
        }
        .widgetURL(CloeDeepLink.chat)
    }

    private var inline: some View {
        Label("Ask Cloe", systemImage: "sparkles")
            .widgetURL(CloeDeepLink.chat)
    }
}
