import AppKit

final class PanelBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill(); bounds.fill()
    }
}
final class GraphView: NSView {
    var values: [Double] = [] { didSet { needsDisplay = true } }
    var ceiling: Double = 1
    override func draw(_ dirtyRect: NSRect) {
        guard !values.isEmpty else { return }
        let line = NSBezierPath(); line.lineWidth = 1.3
        let scale = max(ceiling, values.max() ?? 1, 0.001)
        for (index, value) in values.enumerated() {
            let point = NSPoint(x: CGFloat(index) / CGFloat(max(1, values.count - 1)) * bounds.width,
                                y: 2 + CGFloat(value / scale) * (bounds.height - 4))
            if index == 0 { line.move(to: point) } else { line.line(to: point) }
        }
        if values.count == 1 { line.line(to: NSPoint(x: bounds.maxX, y: line.currentPoint.y)) }
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: bounds.maxX, y: 0)); area.line(to: .zero); area.close()
        NSColor.labelColor.withAlphaComponent(0.06).setFill(); area.fill()
        NSColor.secondaryLabelColor.setStroke(); line.stroke()
    }
}
final class RingView: NSView {
    var value: Double? { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius: CGFloat = 28
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        track.lineWidth = 5
        NSColor.quaternaryLabelColor.setStroke(); track.stroke()
        if let value, value > 0 {
            let arc = NSBezierPath(); arc.lineWidth = 5; arc.lineCapStyle = .round
            arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - min(1, value) * 360, clockwise: true)
            NSColor.labelColor.withAlphaComponent(0.85).setStroke(); arc.stroke()
        }
        let label = value.map(percent) ?? "—"
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold), .foregroundColor: NSColor.labelColor]
        let size = label.size(withAttributes: attributes)
        label.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
    }
}
final class MeterView: NSView {
    var value = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: bounds.width * min(1, max(0, value)), height: bounds.height), xRadius: 3, yRadius: 3).fill()
    }
}
final class MetricRow: NSView {
    let titleLabel = NSTextField(labelWithString: "")
    let valueLabel = NSTextField(labelWithString: "")
    let graph = GraphView()
    let uploadGraph = GraphView()
    let bar = MeterView()
    let ring = RingView()
    init(title: String, percentage: Bool = false) {
        super.init(frame: NSRect(x: 0, y: 0, width: 184, height: 112))
        titleLabel.stringValue = title; titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: percentage ? 10 : 12, weight: .medium)
        valueLabel.maximumNumberOfLines = 2; valueLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 12, y: 88, width: 160, height: 16)
        valueLabel.frame = percentage ? NSRect(x: 88, y: 43, width: 88, height: 34) : NSRect(x: 12, y: 43, width: 160, height: 38)
        ring.frame = NSRect(x: 8, y: 7, width: 76, height: 76); ring.isHidden = !percentage
        graph.frame = percentage ? NSRect(x: 90, y: 16, width: 80, height: 18) : NSRect(x: 12, y: 10, width: 160, height: 24)
        uploadGraph.frame = NSRect(x: 12, y: 10, width: 160, height: 18); uploadGraph.isHidden = true
        bar.frame = NSRect(x: 12, y: 18, width: 160, height: 7)
        for child in [titleLabel, valueLabel, graph, uploadGraph, bar, ring] { addSubview(child) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.withAlphaComponent(0.65).setFill(); card.fill()
        NSColor.separatorColor.withAlphaComponent(0.35).setStroke(); card.lineWidth = 0.5; card.stroke()
    }
    func update(_ text: String, value: Double?, history: Bool = false) {
        valueLabel.stringValue = text; valueLabel.toolTip = text
        ring.value = value
        bar.isHidden = history || value == nil; graph.isHidden = !history
        if let value {
            bar.value = value
            if history { graph.values = Array((graph.values + [value]).suffix(30)) }
        } else if history { graph.values = [] }
        setAccessibilityLabel("\(titleLabel.stringValue): \(ring.isHidden ? "" : value.map(percent) ?? "조회 불가") \(text)")
    }
}
final class PanelController: NSViewController {
    let cpu = MetricRow(title: "CPU", percentage: true)
    let gpu = MetricRow(title: "GPU", percentage: true)
    let temperature = MetricRow(title: "온도")
    let disk = MetricRow(title: "디스크")
    let network = MetricRow(title: "네트워크")
    let memory = MetricRow(title: "메모리", percentage: true)
    let appsStack = NSStackView()
    let scroll = NSScrollView()
    private var icons: [URL: NSImage] = [:]
    private var names: [String] = []
    override func loadView() {
        view = PanelBackground(frame: NSRect(x: 0, y: 0, width: 420, height: 682))
        for (index, tile) in [memory, cpu, gpu, temperature, disk, network].enumerated() {
            tile.frame.origin = NSPoint(x: 18 + (index % 2) * 200, y: 528 - (index / 2) * 124)
            view.addSubview(tile)
        }
        let label = NSTextField(labelWithString: "메모리 상위 20개 앱 + 이 앱")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.frame = NSRect(x: 18, y: 254, width: 384, height: 18); view.addSubview(label)
        scroll.frame = NSRect(x: 18, y: 18, width: 384, height: 232)
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        appsStack.orientation = .vertical; appsStack.alignment = .leading; appsStack.spacing = 2
        scroll.documentView = appsStack; view.addSubview(scroll)
        let quit = NSButton(image: NSImage(systemSymbolName: "power", accessibilityDescription: "종료")!, target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.isBordered = false; quit.contentTintColor = .secondaryLabelColor; quit.toolTip = "종료"
        quit.frame = NSRect(x: 378, y: 650, width: 24, height: 24); view.addSubview(quit)
        temperature.valueLabel.font = .monospacedDigitSystemFont(ofSize: 24, weight: .medium)
        network.valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        network.graph.frame = NSRect(x: 12, y: 29, width: 160, height: 16)
        network.graph.ceiling = 1024; network.uploadGraph.ceiling = 1024
        network.uploadGraph.isHidden = false

    }
    func show(_ reading: DetailReading) {
        let m = reading.memory
        let fraction = m.valid != 0 ? Double(m.used) / Double(m.total) : nil
        memory.update(fraction.map { _ in "\(bytes(m.used)) 사용\n전체 \(bytes(m.total))" } ?? "조회 불가",
                      value: fraction, history: true)
        let pressure = [1: "정상", 2: "주의", 4: "위험"][Int(m.pressure)] ?? "조회 불가"
        let swap = m.swapValid != 0 ? bytes(m.swap) : "조회 불가"
        memory.toolTip = "압축 \(bytes(m.compressed)) · 스왑 \(swap) · 메모리 압박 \(pressure)"
        cpu.update(reading.cpu != nil ? "전체 코어\n사용률" : "샘플링 중…", value: reading.cpu, history: true)
        gpu.update(reading.gpu != nil ? "장치\n사용률" : "조회 불가", value: reading.gpu, history: true)
        let temp = reading.temperature.map { String(format: "%.1f°C", $0) } ?? "센서 조회 불가"
        temperature.update(temp, value: reading.temperature.map { $0 / 60 })
        temperature.toolTip = "배터리 센서 온도 · 시스템 열 상태 \(reading.thermal)"
        disk.update(reading.disk.replacingOccurrences(of: " 여유 / ", with: " 여유\n전체 "), value: reading.diskFraction)
        network.graph.ceiling = 1024
        let speed: String
        if let download = reading.download, let upload = reading.upload {
            speed = "↓ \(bytes(UInt64(download)))/s\n↑ \(bytes(UInt64(upload)))/s"
        } else { speed = reading.network }
        network.update(speed, value: reading.download, history: true)
        if let upload = reading.upload { network.uploadGraph.values = Array((network.uploadGraph.values + [upload]).suffix(30)) }
        else { network.uploadGraph.values = [] }
        network.toolTip = reading.network
        updateApps(reading.apps)
    }
    private func updateApps(_ apps: [AppUsage]) {
        let newNames = apps.map { $0.url?.path ?? $0.name }
        let offset = scroll.contentView.bounds.origin
        if newNames != names {
            for child in appsStack.arrangedSubviews { appsStack.removeArrangedSubview(child); child.removeFromSuperview() }
            for app in apps {
                let row = NSView(frame: NSRect(x: 0, y: 0, width: 365, height: 28))
                row.widthAnchor.constraint(equalToConstant: 365).isActive = true
                row.heightAnchor.constraint(equalToConstant: 28).isActive = true
                let icon = NSImageView(frame: NSRect(x: 0, y: 4, width: 20, height: 20))
                if let url = app.url {
                    if icons[url] == nil { icons[url] = NSWorkspace.shared.icon(forFile: url.path) }
                    icon.image = icons[url]
                }
                let name = NSTextField(labelWithString: app.name)
                name.font = .systemFont(ofSize: 11, weight: app.isSelf ? .semibold : .regular)
                name.lineBreakMode = .byTruncatingTail; name.frame = NSRect(x: 29, y: 5, width: 235, height: 18)
                let amount = NSTextField(labelWithString: bytes(app.memory)); amount.tag = 100
                amount.alignment = .right; amount.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                amount.frame = NSRect(x: 268, y: 5, width: 94, height: 18)
                row.addSubview(icon); row.addSubview(name); row.addSubview(amount); appsStack.addArrangedSubview(row)
            }
            appsStack.frame = NSRect(x: 0, y: 0, width: 365, height: CGFloat(apps.count * 30))
            appsStack.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: names.isEmpty ? NSPoint(x: 0, y: max(0, appsStack.frame.height - scroll.frame.height)) : offset)
            names = newNames
            let keep = Set(apps.compactMap(\.url)); icons = icons.filter { keep.contains($0.key) }
        } else {
            for (row, app) in zip(appsStack.arrangedSubviews, apps) {
                (row.viewWithTag(100) as? NSTextField)?.stringValue = bytes(app.memory)
            }
        }
    }
}
