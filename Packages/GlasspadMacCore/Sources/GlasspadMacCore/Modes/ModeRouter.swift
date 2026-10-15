import Foundation
import GlasspadKit

/// Routes phone-to-Mac `ModeMessage`s to the mode handlers and sends replies through `send`.
@MainActor
public final class ModeRouter {
    public let dock: DockMode
    public let keys: KeysMode
    public let media: MediaMode
    public let deck: DeckMode
    public let clipboard: ClipboardMode
    public let present: PresentMode
    /// Macros mode. nil until the controller wires one in; macro messages are then ignored.
    public var macros: MacroCoordinator?
    public var send: (ModeMessage) -> Void = { _ in }

    private var mediaTimer: Timer?
    private var lastMedia: MediaState?

    public init(poster: EventPoster) {
        let keys = KeysMode(poster: poster)
        self.keys = keys
        self.dock = DockMode()
        self.media = MediaMode(poster: poster)
        self.deck = DeckMode(env: LiveDeckEnvironment(keys: keys))
        self.clipboard = ClipboardMode()
        self.present = PresentMode(keys: keys)
    }

    public func handle(_ message: ModeMessage) {
        switch message {
        case .modeSelected(let mode):
            if mode != .present { present.setLaser(on: false) }
            if mode == .media { startMediaUpdates() } else { stopMediaUpdates() }
            if mode == .macros { macros?.handle(.listMacros) }
        case .dockRequest: send(.dockList(apps: dock.currentList()))
        case .dockOpen(let id): dock.open(bundleID: id)
        case .keysText(let text): keys.type(text)
        case .keysKeystroke(let k): keys.press(k)
        case .mediaRequest:
            lastMedia = nil
            pushMedia()
            startMediaUpdates()
        case .mediaCommand(let c):
            media.send(c)
            pushMedia()
        case .mediaSetVolume(let v): media.setVolume(v)
        case .mediaSetBrightness(let v): media.setBrightness(v)
        case .deckRequest:
            deck.reload()
            send(.deckButtons(deck.config.buttons))
        case .deckRun(let id): send(deck.run(id: id))
        case .clipboardPush(let c): clipboard.push(c)
        case .clipboardPull: send(.clipboardContent(clipboard.pull()))
        case .presentNext: present.next()
        case .presentPrevious: present.previous()
        case .presentLaser(let on): present.setLaser(on: on)
        case .presentLaserPosition(let x, let y): present.moveLaser(x: x, y: y)
        case .macro(let m): macros?.handle(m)
        // Mac -> phone messages: ignore if echoed back.
        case .dockList, .mediaState, .deckButtons, .deckResult, .clipboardContent: break
        }
    }

    /// Session ended: hide the laser, stop polling, forget which icons the phone has.
    public func sessionEnded() {
        present.setLaser(on: false)
        stopMediaUpdates()
        dock.resetSession()
    }

    private func startMediaUpdates() {
        guard mediaTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushMedia() }
        }
        RunLoop.main.add(t, forMode: .common)
        mediaTimer = t
    }

    private func stopMediaUpdates() {
        mediaTimer?.invalidate()
        mediaTimer = nil
    }

    private func pushMedia() {
        media.state { [weak self] state in
            guard let self, state != self.lastMedia else { return }
            self.lastMedia = state
            self.send(.mediaState(state))
        }
    }
}
