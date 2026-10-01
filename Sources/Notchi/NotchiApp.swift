import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config = Config.load()
    private var store: SessionStore!
    private let voiceState = VoiceState()
    private var panel: NotchPanel!
    private var geometry = NotchGeometry.current()
    private var server: HookServer!
    private var speaker: Speaker!
    private var listener: Listener!
    private var brain: Brain!
    private var hotkey: Hotkey!
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private let usagePoller = UsagePoller()
    private var wake: WakeWord!
    private var wakePausedForSpeech = false

    private var skin: Skin { Skin(rawValue: config.skin) ?? .pim }

    func applicationDidFinishLaunching(_ note: Notification) {
        store = SessionStore(config: config)
        setupVoice()
        listener = Listener(language: config.language)
        listener.onLevel = { [weak self] in self?.voiceState.level = $0 }
        listener.onPartial = { [weak self] in self?.store.bubble = $0 }
        Listener.requestPermissions()

        brain = Brain(config: config, lastCwd: { [weak self] in await self?.store.mostRecentCwd })

        store.say = { [weak self] text in self?.say(text) }
        // Peta på Notchi: berätta läget (eller tystna om den redan pratar)
        store.onPoke = { [weak self] in
            guard let self else { return }
            if self.store.speaking {
                self.speaker.stop(); self.store.speaking = false; self.store.bubble = nil
            } else {
                self.say(self.store.spokenStatus())
                if self.config.usagePolling, (self.store.usage.updated ?? .distantPast).timeIntervalSinceNow < -60 {
                    Task { @MainActor in
                        if let r = await self.usagePoller.fetch() { self.store.applyPolled(r) }
                    }
                }
            }
        }

        store.onJump = { [weak self] s in self?.jump(to: s) }

        setupWake()
        setupPanel()
        setupMenu()

        server = HookServer(path: Config.socketPath)
        server.onEvent = { [weak self] e, reply in self?.store.handle(e, reply: reply) }
        server.start()

        hotkey = Hotkey()
        hotkey.onPress = { [weak self] in Task { @MainActor in self?.startListening() } }
        hotkey.onRelease = { [weak self] in Task { @MainActor in self?.stopListening() } }

        // Skärmändringar (extern skärm in/ut)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bringToFront() }
        }
        // Byte av skrivbord/helskärmsapp och väckning ur viloläge: se till att vi ligger överst igen
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.bringToFront() }
            }
        }
        // Livlina: kolla varannan sekund att fönstret syns
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdog() }
        }
        // Användning: hämta direkt var 5:e minut (fungerar oavsett var du kör Claude Code)
        if config.usagePolling {
            Task { @MainActor [weak self] in
                while let self, self.config.usagePolling {
                    if let r = await self.usagePoller.fetch() { self.store.applyPolled(r) }
                    try? await Task.sleep(for: .seconds(300))
                }
            }
        }
        // Musen: avgör själva om den är över notchen (20 ggr/s), med små fördröjningar mot fladder
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
    }

    // MARK: Fönster

    private var hosting: NSHostingView<NotchView>!
    private var enteredAt: Date?
    private var leftAt: Date?
    private var wasDismissed = false
    private var mustLeaveFirst = false   // efter "fäll ihop": öppna inte igen förrän musen lämnat notchen

    private func setupPanel() {
        panel = NotchPanel()
        hosting = NSHostingView(rootView: makeView())
        panel.contentView = hosting
        panel.setFrame(geometry.canvas, display: true)
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()

        // Klick ska bara fångas när notchen är utfälld; annars går de igenom till menyraden.
        // objectWillChange skickas INNAN värdet ändras, så vänta ett varv innan vi läser av läget.
        store.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        let ignore = !self.store.expanded
                        if self.panel.ignoresMouseEvents != ignore { self.panel.ignoresMouseEvents = ignore }
                        self.syncWakeWithSpeech()
                    }
                }
            }
            .store(in: &cancellables)
    }

    private func makeView() -> NotchView {
        NotchView(store: store, voice: voiceState, geometry: geometry)
    }

    private func bringToFront() {
        let g = NotchGeometry.current()
        if g != geometry {
            geometry = g
            hosting?.rootView = makeView()     // ny skärm: rita om med rätt mått
        }
        if panel.frame != geometry.canvas { panel.setFrame(geometry.canvas, display: true) }
        panel.orderFrontRegardless()
    }

    private func watchdog() {
        store.expireStale()
        if !panel.isVisible || !panel.isOnActiveSpace || panel.frame != geometry.canvas
            || NotchGeometry.current() != geometry {
            bringToFront()
        }
    }

    private func trackMouse() {
        let mouse = NSEvent.mouseLocation
        let now = Date()
        // Precis fälld ihop med knappen? Kräv att musen lämnar notchen innan den kan öppnas igen.
        if store.dismissed && !wasDismissed { mustLeaveFirst = true }
        wasDismissed = store.dismissed
        if !store.hovering {
            // Öppna när musen vilat på notchen en kort stund
            let zone = geometry.shapeRect(expanded: false, label: store.shortStatus).insetBy(dx: -2, dy: -3)
            if mustLeaveFirst {
                if !zone.contains(mouse) && !geometry.shapeRect(expanded: true, label: nil).contains(mouse) {
                    mustLeaveFirst = false
                }
                enteredAt = nil
            } else if zone.contains(mouse) {
                if enteredAt == nil { enteredAt = now }
                if now.timeIntervalSince(enteredAt!) > 0.12 {
                    store.hovering = true; store.dismissed = false; leftAt = nil
                }
            } else {
                enteredAt = nil
            }
        } else {
            // Stäng när musen varit utanför den utfällda ytan en stund
            let zone = geometry.shapeRect(expanded: true, label: nil).insetBy(dx: -10, dy: -10)
            if zone.contains(mouse) {
                leftAt = nil
            } else {
                if leftAt == nil { leftAt = now }
                if now.timeIntervalSince(leftAt!) > 0.4 { store.hovering = false; enteredAt = nil }
            }
        }
    }

    // MARK: Meny i menyraden

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "●"
        let menu = NSMenu()
        for s in Skin.allCases {
            let item = NSMenuItem(title: s.displayName, action: #selector(pickSkin(_:)), keyEquivalent: "")
            item.representedObject = s.rawValue
            item.target = self
            item.state = s == skin ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let speak = NSMenuItem(title: "Läs upp händelser", action: #selector(toggleSpeak(_:)), keyEquivalent: "")
        speak.target = self; speak.state = config.speakEvents ? .on : .off
        menu.addItem(speak)
        let wakeItem = NSMenuItem(title: "Lyssna efter ”Hej Notchi”", action: #selector(toggleWake(_:)), keyEquivalent: "")
        wakeItem.target = self; wakeItem.state = config.wakeWord ? .on : .off
        menu.addItem(wakeItem)
        let cfg = NSMenuItem(title: "Öppna inställningar…", action: #selector(openConfig), keyEquivalent: ",")
        cfg.target = self
        menu.addItem(cfg)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Avsluta Notchi", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func pickSkin(_ sender: NSMenuItem) {
        config.skin = sender.representedObject as? String ?? "pim"
        config.save()
        store.config = config
        sender.menu?.items.forEach { if $0.representedObject != nil { $0.state = ($0 === sender) ? .on : .off } }
        store.objectWillChange.send()
        say("Hej! Nu ser jag ut så här.")
    }

    @objc private func toggleSpeak(_ sender: NSMenuItem) {
        config.speakEvents.toggle(); config.save()
        store.config = config
        sender.state = config.speakEvents ? .on : .off
    }

    @objc private func toggleWake(_ sender: NSMenuItem) {
        config.wakeWord.toggle(); config.save()
        store.config = config
        sender.state = config.wakeWord ? .on : .off
        applyWakeSetting(announce: true)
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Config.file)
        // Läs om inställningar när filen sparas går att bygga senare; nu: starta om appen efter ändring.
    }

    // MARK: Röst

    private func setupVoice() {
        let system = SystemSpeaker(language: config.language, identifier: config.systemVoiceIdentifier, rate: config.speechRate)
        if config.voice == "elevenlabs", let key = config.elevenLabsApiKey, let vid = config.elevenLabsVoiceId {
            speaker = ElevenLabsSpeaker(apiKey: key, voiceId: vid, model: config.elevenLabsModel, fallback: system)
        } else {
            speaker = system
        }
        speaker.onLevel = { [weak self] in self?.voiceState.level = $0 }
        speaker.onFinished = { [weak self] in
            guard let self else { return }
            self.store.speaking = false
            let text = self.store.bubble
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if self.store.bubble == text && !self.store.speaking { self.store.bubble = nil }
            }
        }
    }

    private func say(_ text: String) {
        guard !text.isEmpty else { return }
        store.dismissed = false
        store.bubble = text
        // Säkerhetsnät: bubblan försvinner senast efter 25 s även om rösten aldrig säger "klar"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(25))
            if self?.store.bubble == text { self?.store.bubble = nil; self?.store.speaking = false }
        }
        store.speaking = true
        speaker.speak(text)
    }

    // MARK: Hej Notchi

    private func setupWake() {
        wake = WakeWord(language: config.language)
        wake.onWake = { [weak self] in
            guard let self else { return }
            NSSound(named: "Tink")?.play()
            self.store.listening = true
            self.store.dismissed = false
            self.store.bubble = "Ja?"
        }
        wake.onPartial = { [weak self] text in self?.store.bubble = text.isEmpty ? "Ja?" : text }
        wake.onCommand = { [weak self] text in
            guard let self else { return }
            self.store.listening = false
            Task { @MainActor in
                if text.isEmpty { self.say(self.store.spokenStatus()) } else { await self.handle(text) }
                self.wake.resume(.command)
            }
        }
        // Vänta lite så att behörighetsfrågorna hinner besvaras
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.applyWakeSetting(announce: false)
        }
    }

    private func applyWakeSetting(announce: Bool) {
        if config.wakeWord && !wake.supported {
            wake.setEnabled(false)
            if announce || !UserDefaults.standard.bool(forKey: "notchi.wakeUnsupportedShown") {
                UserDefaults.standard.set(true, forKey: "notchi.wakeUnsupportedShown")
                store.showBubble("”Hej Notchi” kräver svensk taligenkänning på enheten. Slå på Diktering i Systeminställningar → Tangentbord och starta om Notchi.", seconds: 14)
            }
            return
        }
        wake.setEnabled(config.wakeWord)
        if announce { say(config.wakeWord ? "Nu lyssnar jag efter hej Notchi." : "Okej, jag slutar lyssna.") }
    }

    /// Lyssna inte medan Notchi själv pratar, så den inte väcker sig själv
    private func syncWakeWithSpeech() {
        guard let wake else { return }
        if store.speaking {
            if !wakePausedForSpeech { wakePausedForSpeech = true; wake.pause(.speaking) }
        } else if wakePausedForSpeech {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(600))   // låt ekot från högtalarna dö ut
                guard let self, !self.store.speaking, self.wakePausedForSpeech else { return }
                self.wakePausedForSpeech = false
                self.wake.resume(.speaking)
            }
        }
    }

    // MARK: Hoppa till sessionen

    private func jump(to s: SessionInfo) {
        let folder = URL(fileURLWithPath: s.cwd)
        guard let path = s.appPath else {
            if !s.cwd.isEmpty { NSWorkspace.shared.open(folder) }
            return
        }
        let app = URL(fileURLWithPath: path)
        let name = app.deletingPathExtension().lastPathComponent.lowercased()
        let editors = ["visual studio code", "code", "cursor", "windsurf", "vscodium", "zed"]
        if editors.contains(where: { name.contains($0) }), !s.cwd.isEmpty {
            // Editorer: öppna projektmappen, så hamnar du i rätt fönster
            NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL?.path == path }) {
            running.activate()
        } else {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
        store.hovering = false
        store.pinned = false
    }

    // MARK: Prata med Notchi

    private func startListening() {
        guard !store.listening else { return }
        wake?.pause(.hotkey)
        speaker.stop()
        store.speaking = false
        store.listening = true
        store.dismissed = false
        store.bubble = "Jag lyssnar…"
        listener.start()
    }

    private func stopListening() {
        guard store.listening else { return }
        Task {
            let text = await listener.finish()
            store.listening = false
            defer { wake?.resume(.hotkey) }
            guard !text.isEmpty else { store.bubble = nil; return }
            await handle(text)
        }
    }

    private func handle(_ text: String) async {
        let intent = IntentRouter.parse(text, hasPending: !store.pending.isEmpty)
        switch intent {
        case .approve:
            guard let p = store.pending.first else { return }
            if p.event.isRisky || !config.voiceApprovals {
                say("Det där behöver du godkänna med ett klick.")
            } else {
                store.resolve(p, allow: true); say("Godkänt!")
            }
        case .deny:
            if let p = store.pending.first { store.resolve(p, allow: false); say("Okej, nekat.") }
        case .stopTalking:
            speaker.stop(); store.speaking = false; store.bubble = nil
        case .status:
            say(store.spokenStatus())
        case .usage:
            say(store.usageSentence() ?? "Jag ser ingen användning än. Den dyker upp efter första svaret i en Claude Code-session.")
        case .openFolder(let name):
            say(await Task.detached { LocalTools.openFolder(name) }.value)
        case .launchApp(let name):
            say(await Task.detached { LocalTools.launchApp(name) }.value)
        case .openAny(let name):
            let result = await Task.detached { () -> String in
                let app = LocalTools.launchApp(name)
                return app.hasPrefix("Jag hittade") ? LocalTools.openFolder(name) : app
            }.value
            say(result)
        case .findFile(let q):
            say(await Task.detached { LocalTools.findFiles(q).summary }.value)
        case .runShortcut(let name):
            say(await Task.detached { LocalTools.runShortcut(name) }.value)
        case .askClaude(let q):
            store.thinkingLocally = true
            store.bubble = "Hmm…"
            let answer = await brain.ask(q) { @MainActor [weak self] progress in
                self?.say(progress)
            }
            store.thinkingLocally = false
            say(answer)
        }
    }
}

// MARK: - Start

@main
enum NotchiMain {
    @MainActor
    static func main() {
        signal(SIGPIPE, SIG_IGN)   // skriv till en hook som redan avslutats ska inte krascha appen
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // ingen ikon i Dock
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
