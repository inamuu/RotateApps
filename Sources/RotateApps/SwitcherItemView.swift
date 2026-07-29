import AppKit

final class SwitcherItemView: NSView {
    static func itemHeight(for size: CGFloat) -> CGFloat {
        thumbnailHeight(for: size) + 59
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
    private let profileBadge = NSTextField(labelWithString: "")
    private let size: CGFloat
    private let windowInfo: WindowInfo
    private let theme: SwitcherTheme

    init(window: WindowInfo, size: CGFloat, showThumbnail: Bool, theme: SwitcherTheme) {
        self.windowInfo = window
        self.size = size
        self.theme = theme
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
        layer?.backgroundColor = theme.cardColor.cgColor

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = theme.thumbnailColor.cgColor
        imageView.image = windowInfo.appIcon
        if showThumbnail {
            loadThumbnail()
        }

        appLabel.stringValue = appDisplayName
        appLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        appLabel.textColor = .labelColor
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.translatesAutoresizingMaskIntoConstraints = false

        profileBadge.stringValue = windowInfo.profileName ?? ""
        profileBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        profileBadge.textColor = .labelColor
        profileBadge.alignment = .center
        profileBadge.lineBreakMode = .byTruncatingTail
        profileBadge.maximumNumberOfLines = 1
        profileBadge.translatesAutoresizingMaskIntoConstraints = false
        profileBadge.isHidden = windowInfo.profileName == nil
        profileBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        profileBadge.wantsLayer = true
        profileBadge.layer?.cornerRadius = 5
        profileBadge.layer?.backgroundColor = theme.accentColor.withAlphaComponent(0.24).cgColor

        titleLabel.stringValue = windowInfo.title
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(appLabel)
        addSubview(profileBadge)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: Self.itemHeight(for: size)),
            appLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            appLabel.trailingAnchor.constraint(lessThanOrEqualTo: profileBadge.leadingAnchor, constant: -6),
            appLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            profileBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            profileBadge.centerYAnchor.constraint(equalTo: appLabel.centerYAnchor),
            profileBadge.widthAnchor.constraint(lessThanOrEqualToConstant: max(48, size * 0.38)),
            profileBadge.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: appLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            titleLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 2),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailHeight(for: size))
        ])
        updateSelection()
    }

    private func updateSelection() {
        layer?.borderColor = isSelected ? theme.accentColor.cgColor : NSColor.clear.cgColor
        layer?.backgroundColor = (isSelected ? theme.accentColor.withAlphaComponent(0.20) : theme.cardColor).cgColor
        profileBadge.layer?.backgroundColor = (isSelected ? theme.accentColor.withAlphaComponent(0.34) : theme.accentColor.withAlphaComponent(0.24)).cgColor
    }

    private var appDisplayName: String {
        guard let profileName = windowInfo.profileName else {
            return windowInfo.ownerName
        }
        return "\(windowInfo.ownerName) - \(profileName)"
    }

    /// Capturing a window is slow enough that doing it while building the panel delays the switcher
    /// itself, so the app icon is shown first and replaced when the capture arrives.
    private func loadThumbnail() {
        let windowID = windowInfo.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let cgImage = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow],
                windowID,
                [.bestResolution, .boundsIgnoreFraming]
            ) else { return }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            DispatchQueue.main.async {
                self?.imageView.image = image
            }
        }
    }
}
