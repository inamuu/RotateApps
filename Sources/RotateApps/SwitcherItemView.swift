import AppKit

final class SwitcherItemView: NSView {
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
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size * 0.92 + 42))
        setup(showThumbnail: showThumbnail)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: size, height: size * 0.92 + 42)
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
            heightAnchor.constraint(equalToConstant: size * 0.92 + 42),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.heightAnchor.constraint(equalToConstant: size * 0.62),
            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            appLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            appLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: appLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: appLabel.trailingAnchor),
            titleLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 2)
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
