import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var panel: PanelController?
    private var collector: Collector?
    private var memoryTimer: Timer?
    private var detailTimer: Timer?
    private let worker = DispatchQueue(label: "k-mac-status.metrics", qos: .utility)
    private var generation = 0
    private var busy = false
    private var sleeping = false
    private var memory = MemoryReading()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: 69)
        item.button?.target = self; item.button?.action = #selector(toggle)
        sampleMemory()
        startMemoryTimer()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        // The status item needs a run-loop layout before it can anchor a popover.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            if CommandLine.arguments.contains("--show-panel") { toggle() }
            if CommandLine.arguments.contains("--lifecycle-test") { lifecycleTest(cycle: 0) }
        }
    }
    private func lifecycleTest(cycle: Int) {
        autoreleasepool { toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [self] in
            precondition(popover.isShown && panel != nil && collector != nil)
            let retained = collector!
            precondition(retained.collections >= 2)
            let closedPanel = panel
            autoreleasepool { popover.close() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self, weak closedPanel] in
                precondition(panel == nil && closedPanel == nil && collector == nil && detailTimer == nil)
                let count = retained.collections
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [self] in
                    precondition(retained.collections == count, "Detail collection continued after close")
                    print("PASS cycle \(cycle + 1): closed panel releases views and stops collecting; footprint \(bytes(own_footprint()))")
                    if cycle < 7 { lifecycleTest(cycle: cycle + 1) }
                    else { NSApp.terminate(nil) }
                }
            }
        }
    }
    private func startMemoryTimer() {
        memoryTimer?.invalidate()
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sampleMemory() }
        memoryTimer?.tolerance = 1
    }
    private func sampleMemory() {
        guard !sleeping else { return }
        memory = read_memory()
        let fraction = memory.valid != 0 ? Double(memory.used) / Double(memory.total) : 0
        let image = NSImage(size: NSSize(width: 21, height: 18), flipped: false) { rect in
            let ring = NSBezierPath(ovalIn: NSRect(x: 3.5, y: 3.5, width: 11, height: 11)); ring.lineWidth = 3
            NSColor.gray.withAlphaComponent(0.45).setStroke(); ring.stroke()
            if fraction > 0 {
                let arc = NSBezierPath(); arc.lineWidth = 3; arc.lineCapStyle = .round
                arc.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 5.5, startAngle: 90,
                              endAngle: 90 - CGFloat(fraction * 360), clockwise: true)
                NSColor.labelColor.setStroke(); arc.stroke()
            }
            return true
        }
        image.isTemplate = true
        item.button?.image = image; item.button?.imagePosition = .imageLeading
        item.button?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        item.button?.title = memory.valid != 0 ? percent(fraction) : "—"
        item.button?.setAccessibilityLabel("메모리 사용률 \(item.button?.title ?? "조회 불가")")
        item.button?.toolTip = "k-mac-status · 메모리 \(bytes(memory.used)) / \(bytes(memory.total))"
    }
    @objc private func toggle() {
        if popover.isShown { popover.close(); return }
        guard let button = item.button else { return }
        generation += 1
        popover.behavior = CommandLine.arguments.contains("--lifecycle-test") ? .applicationDefined : .transient
        popover.delegate = self; popover.animates = false
        let controller = PanelController(); controller.loadViewIfNeeded()
        panel = controller; collector = Collector(); popover.contentViewController = controller
        popover.contentSize = controller.view.frame.size
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        sampleDetails()
        detailTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sampleDetails() }
        detailTimer?.tolerance = 0.2
        let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.generation == token else { return }; self.sampleDetails()
        }
    }
    private func sampleDetails() {
        guard !busy, !sleeping, popover.isShown, let collector else { return }
        busy = true
        let token = generation
        worker.async { [weak self] in
            let reading = autoreleasepool { collector.sample() }
            DispatchQueue.main.async {
                guard let self else { return }
                self.busy = false
                guard self.generation == token, self.popover.isShown else { return }
                autoreleasepool { self.panel?.show(reading) }
            }
        }
    }
    func popoverDidClose(_ notification: Notification) {
        generation += 1; detailTimer?.invalidate(); detailTimer = nil
        popover.contentViewController = nil; panel = nil; collector = nil
        DispatchQueue.main.async { malloc_zone_pressure_relief(nil, 0) }
    }
    @objc private func sleep() {
        sleeping = true; memoryTimer?.invalidate(); memoryTimer = nil
        popover.close()
    }
    @objc private func wake() { sleeping = false; sampleMemory(); startMemoryTimer() }
}

setbuf(stdout, nil)
let app = NSApplication.shared
if CommandLine.arguments.contains("--self-test") {
    let memory = read_memory()
    precondition(memory.valid != 0 && memory.used > 0 && memory.used <= memory.total)
    precondition(own_footprint() > 0)
    let collector = Collector()
    let first = collector.sample()
    Thread.sleep(forTimeInterval: 1)
    let second = collector.sample()
    precondition(first.cpu == nil)
    precondition(second.cpu.map { (0...1).contains($0) } == true)
    precondition(second.apps.filter(\.isSelf).count == 1)
    precondition(second.apps.count <= 21)
    let runningURLs = Set(NSWorkspace.shared.runningApplications
        .filter { $0.activationPolicy == .regular && !$0.isTerminated }.compactMap { $0.bundleURL })
    precondition(second.apps.dropLast().allSatisfy { $0.url.map(runningURLs.contains) == true })
    precondition(second.apps.dropLast().allSatisfy { !$0.isSelf })
    precondition(zip(second.apps.dropLast(), second.apps.dropLast().dropFirst()).allSatisfy { $0.memory >= $1.memory })
    precondition(percent(0.625) == "63%" && percent(1.1) == "100%")
    let panel = PanelController(); panel.loadViewIfNeeded()
    panel.view.appearance = NSAppearance(named: CommandLine.arguments.contains("--light") ? .aqua : .darkAqua)
    panel.show(first); panel.show(second)
    precondition(panel.memory.ring.value != nil && panel.cpu.ring.value != nil)
    precondition(panel.memory.graph.values.count == 2)
    precondition(panel.view.subviews.compactMap { $0 as? NSButton }.count == 1)
    if let position = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > position + 1 {
        let view = panel.view
        let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: image)
        }
        try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[position + 1]))
    }
    print("PASS: memory, CPU delta, top 20 running apps (\(second.apps.count - 1) apps), ranking/self row, formatting, panel render")
    print("memory=\(bytes(memory.used))/\(bytes(memory.total)) GPU=\(second.gpu.map(percent) ?? "unavailable") temperature=\(second.temperature.map { String($0) } ?? "unavailable") network=\(second.network)")
} else {
    let delegate = AppDelegate(); app.delegate = delegate
    app.run()
}
