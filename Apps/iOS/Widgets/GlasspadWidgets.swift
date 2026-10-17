import ActivityKit
import AppIntents
import GlasspadKit
import SwiftUI
import WidgetKit

@main
struct GlasspadWidgets: WidgetBundle {
    var body: some Widget {
        TrackpadControl()
        TrackpadLockScreenWidget()
        ControlsLiveActivity()
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
        .description("Opens Glasspad on Trackpad.")
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
                    Text("Open Trackpad").font(.caption)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        case .accessoryInline:
            Label("Glasspad Trackpad", systemImage: "hand.point.up.left.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "hand.point.up.left.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .widgetAccentable()
            }
            .accessibilityLabel("Open Glasspad Trackpad")
        }
    }
}

// MARK: - Live Activity

/// Remote's or Present's buttons on the Lock Screen and in the Dynamic Island. Each button is
/// an intent that iOS runs in the app, which sends it to the Mac.
struct ControlsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ControlsActivityAttributes.self) { context in
            LiveLockScreenView(controls: context.state, isStale: context.isStale)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let controls = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    KindIcon(kind: controls.kind)
                        .font(.title2)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let present = controls.present {
                        LiveClock(present: present, isStale: context.isStale)
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Headline(controls: controls)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    LiveButtons(controls: controls, size: 44)
                        .padding(.top, 4)
                }
            } compactLeading: {
                KindIcon(kind: controls.kind)
            } compactTrailing: {
                CompactState(controls: controls, isStale: context.isStale)
            } minimal: {
                CompactState(controls: controls, isStale: context.isStale)
            }
        }
        // Apple Watch Smart Stack and CarPlay show the Lock Screen view at the small size.
        .supplementalActivityFamilies([.small])
    }
}

private struct LiveLockScreenView: View {
    let controls: LiveControls
    let isStale: Bool
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            small
        } else {
            medium
        }
    }

    /// Apple Watch and CarPlay: the same parts, smaller, and the buttons without words.
    private var small: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                KindIcon(kind: controls.kind)
                    .font(.caption)
                Text(controls.remote?.title ?? "Presenting")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if let present = controls.present {
                    LiveClock(present: present, isStale: isStale)
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
            }
            LiveButtons(controls: controls, size: 30, compact: true)
        }
        .padding(8)
    }

    private var medium: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KindIcon(kind: controls.kind)
                    .font(.title3)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(.quaternary))
                Headline(controls: controls, leading: true)
                Spacer(minLength: 4)
                if let present = controls.present {
                    LiveClock(present: present, isStale: isStale)
                        .font(.title.weight(.semibold).monospacedDigit())
                }
            }
            LiveButtons(controls: controls, size: 48)
        }
        .padding(16)
    }
}

/// What plays and where, or which Mac the slides are on. A press that failed says why instead.
private struct Headline: View {
    let controls: LiveControls
    var leading = false

    var body: some View {
        VStack(alignment: leading ? .leading : .center, spacing: 2) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            if let problem = controls.problem {
                Label(problem, systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        controls.remote?.title ?? "Presenting"
    }

    private var detail: String {
        if let detail = controls.remote?.detail { return "\(detail) on \(controls.macName)" }
        return "On \(controls.macName)"
    }
}

private struct KindIcon: View {
    let kind: LiveControls.Kind

    var body: some View {
        Image(systemName: kind == .remote ? "appletvremote.gen4.fill" : "play.rectangle.fill")
            .accessibilityHidden(true)
    }
}

/// Remote: Back, Play or Pause, Forward. Present: Back and Next, Next the wider one, as in the app.
private struct LiveButtons: View {
    let controls: LiveControls
    let size: CGFloat
    /// Small sizes (Apple Watch, CarPlay): Present's buttons drop their words and share the width.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            if let remote = controls.remote {
                if remote.hasBack {
                    LiveButton(intent: LiveSkipBackIntent(), symbol: remote.backSymbol,
                               label: remote.backLabel, size: size)
                }
                LiveButton(intent: LivePlayPauseIntent(), symbol: remote.isPlaying ? "pause.fill" : "play.fill",
                           label: remote.isPlaying ? "Pause" : "Play", size: size, prominent: true)
                if remote.hasForward {
                    LiveButton(intent: LiveSkipForwardIntent(), symbol: remote.forwardSymbol,
                               label: remote.forwardLabel, size: size)
                }
            } else {
                LiveButton(intent: LivePreviousSlideIntent(), symbol: "chevron.left", label: "Previous slide",
                           size: size, title: compact ? nil : "Back")
                    .frame(width: compact ? nil : 112)
                LiveButton(intent: LiveNextSlideIntent(), symbol: "chevron.right", label: "Next slide",
                           size: size, prominent: true, title: compact ? nil : "Next")
            }
        }
    }
}

private struct LiveButton<Intent: LiveActivityIntent>: View {
    let intent: Intent
    let symbol: String
    let label: String
    let size: CGFloat
    var prominent = false
    var title: String?

    var body: some View {
        Button(intent: intent) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                if let title {
                    Text(title).font(.headline)
                }
            }
            .frame(maxWidth: .infinity, minHeight: size)
            .background(Capsule().fill(prominent ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The talk timer: counts up, or down to the talk length and then the time over in red. The
/// system draws it from dates, so the app sends nothing while it counts.
private struct LiveClock: View {
    let present: LiveControls.Present
    let isStale: Bool

    var body: some View {
        Group {
            if let start = present.countingFrom {
                if let end = present.endsAt {
                    if isStale {
                        // Past the length: the time over, counting up from the end.
                        Text("+\(Text(end, style: .timer))").foregroundStyle(.red)
                    } else {
                        Text(timerInterval: start...end, countsDown: true)
                    }
                } else {
                    Text(start, style: .timer)
                }
            } else {
                Text(present.pausedText).foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.trailing)
        .lineLimit(1)
    }
}

/// The compact Dynamic Island's right side: the timer, or whether it plays.
private struct CompactState: View {
    let controls: LiveControls
    let isStale: Bool

    var body: some View {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            DynamicIslandWidth { limited in content(limited: limited) }
        } else {
            content(limited: false)
        }
        #else
        content(limited: false)
        #endif
    }

    /// `limited`: iOS 27 shows the compact and minimal Dynamic Island in landscape too, where it
    /// cannot grow wider, so the timer gets less room there and shrinks to fit.
    @ViewBuilder private func content(limited: Bool) -> some View {
        if let present = controls.present {
            LiveClock(present: present, isStale: isStale)
                .font(.caption.weight(.semibold).monospacedDigit())
                .minimumScaleFactor(limited ? 0.7 : 1)
                .frame(maxWidth: limited ? 40 : 52)
        } else if let remote = controls.remote {
            Image(systemName: remote.isPlaying ? "pause.fill" : "play.fill")
                .accessibilityLabel(remote.isPlaying ? "Playing" : "Paused")
        }
    }
}

#if compiler(>=6.4)
/// Reads whether the Dynamic Island is held to its narrow width (landscape on iOS 27).
@available(iOS 27.0, *)
private struct DynamicIslandWidth<Content: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var limited
    @ViewBuilder let content: (Bool) -> Content

    var body: some View { content(limited) }
}
#endif
