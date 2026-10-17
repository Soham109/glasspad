import AppKit
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
    /// Keeps the Mac's own Dock out of the way (the phone and the menu both switch it).
    public let macDock: MacDockHider
    /// Macros mode. nil until the controller wires one in; macro messages are then ignored.
    public var macros: MacroCoordinator? {
        didSet {
            guard let live = deckEnvironment else { return }
            live.macroRunner = { [weak self] id in
                guard let macros = self?.macros else { return (false, "Macros are not ready") }
                let result = await macros.run(id, trigger: .deck)
                if case .failed(let e) = result.outcome { return (false, e.description) }
                return (true, nil)
            }
        }
    }
    /// Displays mode. The app sets the live one; tests set one with a fake backend.
    public var displays: DisplaysMode? { didSet { wireDisplays() } }
    public var send: (ModeMessage) -> Void = { _ in }

    private let deckEnvironment: LiveDeckEnvironment?
    private var mediaTimer: Timer?
    private var lastMedia: MediaState?
    /// The phone's current screen; Dock updates are pushed only while it shows Dock or Deck.
    public private(set) var phoneMode: GlasspadMode?
    /// Every mode on the phone's screen: `phoneMode`, plus the other panes of a layout
    /// (`modesShown`). The frontmost app and Dock pushes go to any of them.
    public private(set) var phoneModes: Set<GlasspadMode> = []
    private var wantsFrontmost: Bool { !phoneModes.isDisjoint(with: [.dock, .deck, .remote]) }
    private var dockPushPending = false
    private var workspaceObservers: [NSObjectProtocol] = []
    /// A session ended; the Dock comes back unless a new one starts within this delay. Locking
    /// the phone ends the session (the app says bye when it goes to the background), so a short
    /// grace restarted the Dock twice on every lock and unlock: once to show it, once to hide it
    /// again, closing Mission Control and Launchpad each time. 30 s covers a glance at the lock
    /// screen; a real goodbye still brings the Dock back.
    public static let defaultDisconnectGrace: TimeInterval = 30
    public var disconnectGrace: TimeInterval = ModeRouter.defaultDisconnectGrace
    private var disconnectTask: Task<Void, Never>?
    /// False for the live check: messages it sends are not a phone connecting, so the Dock does
    /// not hide "while connected".
    public var tracksSession = true

    public init(poster: EventPoster, macDock: MacDockHider = .shared, observeWorkspace: Bool = true) {
        let keys = KeysMode.live(poster: poster)
        self.keys = keys
        self.dock = DockMode()
        let media = MediaMode(poster: poster)
        self.media = media
        let env = LiveDeckEnvironment(keys: keys, media: media)
        self.deckEnvironment = env
        let deck = DeckMode(env: env)
        self.deck = deck
        MacControlRelay.shared.perform = { [weak deck] action in
            await deck?.perform(.system(action)) ?? DeckMode.Outcome(ok: false, message: "Glasspad is shutting down.")
        }
        self.clipboard = ClipboardMode()
        self.present = PresentMode(keys: keys)
        self.macDock = macDock
        macDock.recoverAfterCrash()
        macDock.onChange = { [weak self] state in self?.send(.macDockState(state)) }
        media.onChange = { [weak self] in self?.pushMedia() }
        if observeWorkspace { startWorkspaceObservers() }
        displays = DisplaysMode(backend: LiveDisplays())
        wireDisplays()
        keys.onLayoutChange = { [weak self] in MainActor.assumeIsolated { self?.keyLayoutChanged() } }
    }

    /// The user switched the Mac's keyboard layout: the phone's keyboard follows while shown.
    private func keyLayoutChanged() {
        guard phoneModes.contains(.keys) else { return }
        send(.keysLayout(keys.letters()))
    }

    /// Displays answers through `send` and sends icons from the Dock's cache.
    private func wireDisplays() {
        displays?.send = { [weak self] in self?.send($0) }
        displays?.icons = { [weak self] ids in self?.dock.icons(for: ids) ?? [] }
        displays?.nightShift = { NightShift.isOn() }
    }

    /// For tests: every part injected, nothing observed.
    public init(keys: KeysMode, dock: DockMode, media: MediaMode, deck: DeckMode, clipboard: ClipboardMode,
                present: PresentMode, macDock: MacDockHider) {
        self.keys = keys
        self.dock = dock
        self.media = media
        self.deck = deck
        self.clipboard = clipboard
        self.present = present
        self.macDock = macDock
        self.deckEnvironment = nil
        keys.onLayoutChange = { [weak self] in MainActor.assumeIsolated { self?.keyLayoutChanged() } }
        macDock.onChange = { [weak self] state in self?.send(.macDockState(state)) }
        media.onChange = { [weak self] in self?.pushMedia() }
    }

    public func handle(_ message: ModeMessage) {
        sessionActive()
        switch message {
        case .modeSelected(let mode):
            phoneMode = mode
            phoneModes = [mode]
            if mode == .keys { send(.keysLayout(keys.letters())) }
            if mode != .present { present.setLaser(on: false) }
            if mode == .media || mode == .remote { startMediaUpdates() } else { stopMediaUpdates() }
            if mode == .macros { macros?.handle(.listMacros) }
            if mode == .dock || mode == .deck || mode == .remote { send(.frontmostApp(bundleID: dock.workspace.frontmostBundleID())) }
        case .modesShown(let modes):
            let before = wantsFrontmost
            let hadKeys = phoneModes.contains(.keys)
            phoneModes = Set(modes).union(phoneMode.map { [$0] } ?? [])
            if phoneModes.contains(.keys) && !hadKeys { send(.keysLayout(keys.letters())) }
            if wantsFrontmost && !before { send(.frontmostApp(bundleID: dock.workspace.frontmostBundleID())) }
        case .dockRequest:
            sendDockList(dock.currentList())
            send(.macDockState(macDock.state))
        case .dockSync(let keys):
            dock.phoneHas(iconKeys: keys)
            sendDockList(dock.currentList())
            send(.macDockState(macDock.state))
        case .dockOpen(let id):
            dock.open(bundleID: id) { [weak self] outcome in
                self?.send(.dockOpenResult(bundleID: id, ok: outcome.ok, message: outcome.message))
                self?.scheduleDockPush()
            }
        case .dockAppAction(let id, let action):
            let ok = dock.perform(action, bundleID: id)
            if !ok {
                send(.dockOpenResult(bundleID: id, ok: false, message: "\(action == .revealInFinder ? "Could not find" : "Not running:") \(id)"))
            }
            scheduleDockPush()
        case .dockCatalogRequest: send(.dockCatalog(apps: dock.catalog()))
        case .dockIconRequest(let ids):
            for batch in DockMode.iconBatches(dock.icons(for: ids)) { send(.dockIcons(apps: batch)) }
        case .macDockSet(let state): macDock.set(state)
        case .keysText(let text): keys.type(text)
        case .keysKeystroke(let k): keys.press(k)
        case .mediaRequest:
            lastMedia = nil
            media.phoneWantsEverything()
            pushMedia()
            startMediaUpdates()
        case .mediaCommand(let c):
            media.send(c)
            pushMedia()
        case .mediaSetVolume(let v): media.setVolume(v)
        case .mediaSetBrightness(let v): media.setBrightness(v)
        case .mediaControl(let c):
            media.control(c)
            pushMedia()
        case .deckRequest:
            deck.reload()
            sendDeck()
        case .deckRun(let id): runDeck(id, confirmed: false)
        case .deckRunConfirmed(let id): runDeck(id, confirmed: true)
        case .deckSave(let layout):
            let result = deck.savePhoneEdit(layout)
            send(result)
            sendDeck()
        case .deckCatalogRequest:
            Task { [weak self] in
                guard let self else { return }
                let catalog = await self.deck.catalog()
                self.send(.deckCatalog(catalog))
            }
        case .clipboardPush(let c):
            let refusal = clipboard.push(c)
            send(.clipboardPushResult(ok: refusal == nil, message: refusal))
        case .clipboardPull:
            Task { [weak self] in
                guard let self else { return }
                switch await self.clipboard.pullResult() {
                case .content(let content): self.send(.clipboardContent(content))
                case .empty: self.send(.clipboardContent(nil))
                case .tooLarge, .imageNotSendable, .notAllowed:
                    // The reason first; the nil after it is all an older phone understands.
                    if let reason = self.clipboard.lastRefusal { self.send(.clipboardPullRefused(message: reason)) }
                    self.send(.clipboardContent(nil))
                }
            }
        case .presentNext: present.next()
        case .presentPrevious: present.previous()
        case .presentLaser(let on): present.setLaser(on: on)
        case .presentLaserPosition(let x, let y): present.moveLaser(x: x, y: y)
        case .remoteSystem(let id, let action):
            // Only the one-tap controls; anything that needs confirming is pinned in Actions, which asks first.
            guard !action.needsConfirmation else {
                send(.deckResult(id: id, ok: false, message: "Pin it in Actions to use it."))
                return
            }
            Task { [weak self] in
                guard let self else { return }
                let outcome = await self.deck.perform(.system(action))
                // On success the message is the new state of a switch ("Do Not Disturb is on"), as for Deck runs.
                self.send(.deckResult(id: id, ok: outcome.ok, message: outcome.message))
            }
        case .displaysWatch(let on): displays?.watch(on)
        case .windowCommand(let id, let window, let command): displays?.handle(id: id, windowID: window, command: command)
        case .displayCommand(let id, let command): displays?.handle(id: id, command: command)
        case .windowHighlight(let window): displays?.highlight(windowID: window)
        case .macro(let m): macros?.handle(m)
        // Mac -> phone messages: ignore if echoed back.
        case .keysLayout, .dockList, .mediaState, .deckButtons, .deckResult, .clipboardContent, .dockOpenResult,
             .clipboardPushResult, .clipboardPullRefused, .dockCatalog,
             .dockIcons, .frontmostApp, .macDockState, .deckLayout, .deckSaveResult, .deckCatalog, .deckImage,
             .displaysState, .displaysResult:
            break
        }
    }

    /// The Dock list, with icons beyond one message's share following in their own messages,
    /// so a first sync of a full Dock never becomes one huge message.
    private func sendDockList(_ apps: [DockApp]) {
        let (list, later) = DockMode.splitIcons(apps)
        send(.dockList(apps: list))
        for batch in DockMode.iconBatches(later) { send(.dockIcons(apps: batch)) }
    }

    private func sendDeck() {
        let layout = deck.config.layout
        send(.deckButtons(layout.allButtons.filter { $0.action != .folder }))
        send(.deckLayout(layout))
    }

    private func runDeck(_ id: UUID, confirmed: Bool) {
        Task { [weak self] in
            guard let self else { return }
            for reply in await self.deck.run(id: id, confirmed: confirmed) { self.send(reply) }
        }
    }

    /// A message arrived, so a phone is connected now.
    private func sessionActive() {
        guard tracksSession else { return }
        disconnectTask?.cancel()
        disconnectTask = nil
        macDock.setConnected(true)
    }

    /// Session ended: hide the laser, stop polling, forget which icons the phone has, and put
    /// the Mac's Dock back after a short grace period (unless the manual switch keeps it hidden).
    public func sessionEnded() {
        present.setLaser(on: false)
        keys.restoreInputMethod()
        stopMediaUpdates()
        displays?.sessionEnded()
        dock.resetSession()
        phoneMode = nil
        phoneModes = []
        disconnectTask?.cancel()
        let grace = disconnectGrace
        disconnectTask = Task { [weak self] in
            if grace > 0 { try? await Task.sleep(for: .seconds(grace)) }
            guard !Task.isCancelled else { return }
            self?.macDock.setConnected(false)
        }
    }

    /// The Mac app is quitting.
    public func appWillTerminate() {
        disconnectTask?.cancel()
        keys.restoreInputMethod()
        macDock.appWillTerminate()
        present.setLaser(on: false)
    }

    // MARK: Live Dock updates

    private func startWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                                          NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                                          NSWorkspace.didUnhideApplicationNotification]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let id = app?.bundleIdentifier, appName = app?.localizedName, url = app?.bundleURL
                let activated = note.name == NSWorkspace.didActivateApplicationNotification && app?.activationPolicy == .regular
                MainActor.assumeIsolated { [weak self] in
                    self?.workspaceChanged(activated: activated ? id : nil, name: appName, url: url)
                }
            }
            workspaceObservers.append(token)
        }
    }

    func workspaceChanged(activated bundleID: String?, name: String?, url: URL?) {
        if let bundleID {
            dock.noteActivated(DockMode.Entry(bundleID: bundleID, name: name ?? bundleID, url: url))
            if wantsFrontmost { send(.frontmostApp(bundleID: bundleID)) }
        }
        scheduleDockPush()
    }

    /// Pushes a fresh Dock list (running dots, frontmost) shortly after a change, while Dock shows.
    private func scheduleDockPush() {
        guard phoneModes.contains(.dock), !dockPushPending else { return }
        dockPushPending = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self else { return }
            self.dockPushPending = false
            if self.phoneModes.contains(.dock) { self.sendDockList(self.dock.currentList()) }
        }
    }

    // MARK: Media

    private func startMediaUpdates() {
        media.setActive(true)
        guard mediaTimer == nil else { return }
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushMedia() }
        }
        RunLoop.main.add(t, forMode: .common)
        mediaTimer = t
    }

    private func stopMediaUpdates() {
        media.setActive(false)
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
