import ActivityKit
import SwiftUI
import WidgetKit

struct CloeQuickAccessActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CloeActivityAttributes.self) { context in
            // Lock Screen / banner presentation. This is the ONLY surface a phone
            // without a Dynamic Island ever shows, so it's where the design lives.
            LockScreenView(state: context.state, label: context.attributes.label)
                .activityBackgroundTint(.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            // Required by the API even though Cloe doesn't target the Dynamic Island.
            // Minimal stubs: functional on DI phones, never shown on non-DI phones.
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Label(context.state.headline, systemImage: "sparkles")
                        .font(.headline)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Image(systemName: context.state.phase == .thinking ? "ellipsis" : "mic.fill")
            } minimal: {
                Image(systemName: "sparkles")
            }
            .widgetURL(CloeDeepLink.chat)
        }
    }
}

/// The glanceable quick-access row: tap the body to open chat, tap the mic to talk.
private struct LockScreenView: View {
    let state: CloeActivityAttributes.ContentState
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            // Whole row (except the mic) opens the chat.
            Link(destination: CloeDeepLink.chat) {
                HStack(spacing: 12) {
                    glyph
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(state.headline)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }

            // Mic shortcut → open the app and start hands-free voice.
            Link(destination: CloeDeepLink.voice) {
                Image(systemName: "mic.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: Circle())
            }
        }
        .padding()
    }

    @ViewBuilder
    private var glyph: some View {
        Group {
            if state.phase == .thinking {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 40, height: 40)
        .background(.white.opacity(0.15), in: Circle())
    }
}
