import AppKit

final class SwitcherPanel: NSPanel {
    private let content = NSStackView()
    private let settings: SettingsStore
    private var itemViews: [SwitcherItemView] = []
    private var itemViewsByWindowID: [CGWindowID: SwitcherItemView] = [:]
    private var visibleWindowIDs: [CGWindowID] = []
    private var currentLayout: GridLayout?
    private var currentStyle: ItemStyle?

    /// Everything an item view bakes in at creation time; a change here forces new views.
    private struct ItemStyle: Equatable {
        let itemSize: CGFloat
        let showThumbnails: Bool
        let theme: SwitcherTheme
    }

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

    /// The panel is kept alive between sessions, so hiding is an `orderOut` rather than a close.
    func hide() {
        orderOut(nil)
    }

    /// Item views are reused by window ID: a refresh that only changes labels or badges touches
    /// nothing else, and only a change in membership or geometry re-lays the grid.
    func update(windows: [WindowInfo], selectedIndex: Int) {
        let ids = windows.map(\.id)
        let layout = gridLayout(itemCount: windows.count)
        let style = ItemStyle(itemSize: layout.itemSize, showThumbnails: settings.showThumbnails, theme: settings.theme)

        if style != currentStyle {
            itemViewsByWindowID.removeAll()
            currentStyle = style
        }

        var views: [SwitcherItemView] = []
        views.reserveCapacity(windows.count)
        for window in windows {
            if let existing = itemViewsByWindowID[window.id] {
                existing.update(window: window)
                views.append(existing)
            } else {
                let view = SwitcherItemView(window: window, size: style.itemSize, showThumbnail: style.showThumbnails, theme: style.theme)
                itemViewsByWindowID[window.id] = view
                views.append(view)
            }
        }
        let liveIDs = Set(ids)
        itemViewsByWindowID = itemViewsByWindowID.filter { liveIDs.contains($0.key) }
        itemViews = views

        if ids != visibleWindowIDs || layout != currentLayout {
            content.arrangedSubviews.forEach { row in
                content.removeArrangedSubview(row)
                (row as? NSStackView)?.arrangedSubviews.forEach { item in
                    (row as? NSStackView)?.removeArrangedSubview(item)
                    item.removeFromSuperview()
                }
                row.removeFromSuperview()
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
