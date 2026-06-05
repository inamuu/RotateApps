import AppKit

final class SwitcherPanel: NSPanel {
    private let content = NSStackView()
    private let settings: SettingsStore
    private var itemViews: [SwitcherItemView] = []
    private var visibleWindowIDs: [CGWindowID] = []
    private var currentLayout: GridLayout?

    private struct GridLayout: Equatable {
        let columns: Int
        let rows: Int
        let itemSize: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    init(settings: SettingsStore) {
        self.settings = settings
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: min(980, screenFrame.width * 0.82), height: 260),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        setupContent()
    }

    func show() {
        centerOnScreen()
        orderFrontRegardless()
    }

    func update(windows: [WindowInfo], selectedIndex: Int) {
        let ids = windows.map(\.id)
        let layout = gridLayout(itemCount: windows.count)

        if ids != visibleWindowIDs || layout != currentLayout {
            content.arrangedSubviews.forEach { view in
                content.removeArrangedSubview(view)
                view.removeFromSuperview()
            }
            itemViews = windows.map {
                SwitcherItemView(window: $0, size: layout.itemSize, showThumbnail: settings.showThumbnails, theme: settings.theme)
            }

            for rowIndex in 0..<layout.rows {
                let row = NSStackView()
                row.orientation = .horizontal
                row.alignment = .top
                row.spacing = 10

                let start = rowIndex * layout.columns
                let end = min(start + layout.columns, itemViews.count)
                guard start < end else { continue }
                for item in itemViews[start..<end] {
                    row.addArrangedSubview(item)
                }
                content.addArrangedSubview(row)
            }
            visibleWindowIDs = ids
            currentLayout = layout
            layoutPanel(layout)
        }

        for (index, item) in itemViews.enumerated() {
            item.isSelected = index == selectedIndex
        }
    }

    private func setupContent() {
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.masksToBounds = true
        root.translatesAutoresizingMaskIntoConstraints = false

        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 10
        content.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        content.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(content)
        contentView = root
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    private func layoutPanel(_ layout: GridLayout) {
        setFrame(NSRect(x: frame.origin.x, y: frame.origin.y, width: layout.width, height: layout.height), display: true)
        centerOnScreen()
    }

    private func gridLayout(itemCount: Int) -> GridLayout {
        guard itemCount > 0 else {
            return GridLayout(columns: 1, rows: 1, itemSize: settings.itemSize, width: settings.itemSize + 24, height: SwitcherItemView.itemHeight(for: settings.itemSize) + 24)
        }

        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxWidth = visibleFrame.width * 0.92
        let maxHeight = visibleFrame.height * 0.84
        let gap: CGFloat = 10
        let padding: CGFloat = 24

        var itemSize = settings.itemSize
        var columns = min(itemCount, max(1, Int((maxWidth - padding + gap) / (itemSize + gap))))
        var rows = Int(ceil(Double(itemCount) / Double(columns)))
        var itemHeight = SwitcherItemView.itemHeight(for: itemSize)
        var height = CGFloat(rows) * itemHeight + CGFloat(max(0, rows - 1)) * gap + padding

        while height > maxHeight, columns < itemCount {
            columns += 1
            rows = Int(ceil(Double(itemCount) / Double(columns)))
            height = CGFloat(rows) * itemHeight + CGFloat(max(0, rows - 1)) * gap + padding
        }

        if height > maxHeight {
            let availableItemHeight = (maxHeight - padding - CGFloat(max(0, rows - 1)) * gap) / CGFloat(rows)
            itemSize = max(82, min(itemSize, (availableItemHeight - 59) / 0.52))
            columns = min(itemCount, max(1, Int((maxWidth - padding + gap) / (itemSize + gap))))
            rows = Int(ceil(Double(itemCount) / Double(columns)))
        }

        itemHeight = SwitcherItemView.itemHeight(for: itemSize)
        let width = min(maxWidth, CGFloat(columns) * itemSize + CGFloat(max(0, columns - 1)) * gap + padding)
        let finalHeight = min(maxHeight, CGFloat(rows) * itemHeight + CGFloat(max(0, rows - 1)) * gap + padding)
        return GridLayout(columns: columns, rows: rows, itemSize: itemSize, width: width, height: finalHeight)
    }

    private func centerOnScreen() {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = NSPoint(
            x: visibleFrame.midX - frame.width / 2,
            y: visibleFrame.midY - frame.height / 2
        )
        setFrameOrigin(origin)
    }
}
