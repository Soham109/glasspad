import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct GlasspadWidgets: WidgetBundle {
    var body: some Widget {
        TrackpadControl()
        TrackpadLockScreenWidget()
        TrackpadLiveActivity()
    }
}

// MARK: - Control Center

/// A Control Center (and Lock Screen / Action button) control that opens the trackpad.
struct TrackpadControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.soham109.glasspad.control.trackpad") {
            ControlWidgetButton(action: OpenTrackpadIntent()) {
                Label("Trackpad", systemImage: "hand.point.up.left.fill")
            }
        }
        .displayName("Glasspad Trackpad")
        .description("Opens your iPhone as a trackpad for your Mac.")
    }
}

// MARK: - Lock Screen widget

private struct StaticEntry: TimelineEntry {
    let date: Date
}

private struct StaticProvider: TimelineProvider {
    func placeholder(in context: Context) -> StaticEntry { StaticEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (StaticEntry) -> Void) {
        completion(StaticEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<StaticEntry>) -> Void) {
        completion(Timeline(entries: [StaticEntry(date: .now)], policy: .never))
    }
}

/// A Lock Screen widget that opens the trackpad with one tap.
struct TrackpadLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.soham109.glasspad.widget.trackpad", provider: StaticProvider()) { _ in
            LockScreenView()
                .widgetURL(GlasspadLink.trackpad)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Trackpad")
        .description("Open Glasspad on the trackpad.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct LockScreenView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "hand.point.up.left.fill")
                    .font(.title2)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Glasspad").font(.headline).widgetAccentable()
                    Text("Open trackpad").font(.caption)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        case .accessoryInline:
            Label("Glasspad trackpad", systemImage: "hand.point.up.left.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .widgetAccentable()
            }
            .accessibilityLabel("Open Glasspad trackpad")
        }
    }
}

// MARK: - Live Activity

/// Connection state while the trackpad is in use: on the Lock Screen and in the Dynamic Island.
struct TrackpadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackpadActivityAttributes.self) { context in
            LiveLockScreenView(state: context.state)
                .activityBackgroundTint(nil)
                .widgetURL(GlasspadLink.trackpad)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hand.point.up.left.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusDot(status: context.state.status, size: 10)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.macName).font(.headline).lineLimit(1)
                        Text(context.state.title).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "hand.point.up.left.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                StatusDot(status: context.state.status, size: 8)
            } minimal: {
                StatusDot(status: context.state.status, size: 8)
            }
            .widgetURL(GlasspadLink.trackpad)
        }
    }
}

private struct LiveLockScreenView: View {
    let state: TrackpadActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(.quaternary)
                Image(systemName: "hand.point.up.left.fill")
                    .font(.title3)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Glasspad")
                    .font(.headline)
                Text(state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                StatusDot(status: state.status, size: 8)
                Text(state.title)
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

private struct StatusDot: View {
    let status: TrackpadActivityAttributes.ContentState.Status
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .accessibilityLabel(Text(status.rawValue))
    }

    private var color: Color {
        switch status {
        case .connected: .green
        case .connecting: .orange
        case .paused: .gray
        case .offline: .red
        }
    }
}
