import AppKit

final class SwitcherItemView: NSView {
    static func itemHeight(for size: CGFloat) -> CGFloat {
        thumbnailHeight(for: size) + 51
    }

    static func thumbnailHeight(for size: CGFloat) -> CGFloat {
        max(48, size * 0.52)
    }

    var isSelected: Bool = false {
        didSet { updateSelection() }
    }

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private let size: CGFloat
    private let windowInfo: WindowInfo

    init(window: WindowInfo, size: CGFloat, showThumbnail: Bool) {
        self.windowInfo = window
        self.size = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: Self.itemHeight(for: size)))
        setup(showThumbnail: showThumbnail)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: size, height: Self.itemHeight(for: size))
    }

    private func setup(showThumbnail: Bool) {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 2
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.24).cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        imageView.image = showThumbnail ? thumbnail() ?? windowInfo.appIcon : windowInfo.appIcon

        appLabel.stringValue = windowInfo.ownerName
        appLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        appLabel.textColor = .labelColor
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = windowInfo.title
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(appLabel)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: Self.itemHeight(for: size)),
            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            appLabel.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: appLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: appLabel.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 2),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailHeight(for: size))
        ])
        updateSelection()
    }

    private func updateSelection() {
        layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.windowBackgroundColor.withAlphaComponent(0.24)).cgColor
    }

    private func thumbnail() -> NSImage? {
        guard let cgImage = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow],
            windowInfo.id,
            [.bestResolution, .boundsIgnoreFraming]
        ) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
