import AppKit

/// A stable colour per profile name, so the same Chrome profile always shows up in the same colour.
enum ProfilePalette {
    private static let colors: [NSColor] = [
        NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.95, alpha: 1), // blue
        NSColor(calibratedRed: 0.92, green: 0.44, blue: 0.20, alpha: 1), // orange
        NSColor(calibratedRed: 0.22, green: 0.70, blue: 0.45, alpha: 1), // green
        NSColor(calibratedRed: 0.80, green: 0.32, blue: 0.70, alpha: 1), // purple
        NSColor(calibratedRed: 0.90, green: 0.30, blue: 0.35, alpha: 1), // red
        NSColor(calibratedRed: 0.15, green: 0.68, blue: 0.72, alpha: 1), // teal
        NSColor(calibratedRed: 0.85, green: 0.65, blue: 0.10, alpha: 1), // amber
        NSColor(calibratedRed: 0.50, green: 0.45, blue: 0.90, alpha: 1)  // indigo
    ]

    static func color(for name: String) -> NSColor {
        // FNV-1a keeps the mapping stable across launches, unlike `hashValue`.
        var hash: UInt32 = 2_166_136_261
        for byte in name.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return colors[Int(hash % UInt32(colors.count))]
    }
}

final class SwitcherItemView: NSView {
    static func itemHeight(for size: CGFloat) -> CGFloat {
        thumbnailHeight(for: size) + 59
    }

    static func thumbnailHeight(for size: CGFloat) -> CGFloat {
        max(48, size * 0.52)
    }

    /// How old a cached thumbnail may be before the switcher re-captures it in the background.
    private static let thumbnailMaxAge: TimeInterval = 2

    var isSelected: Bool = false {
        didSet { updateSelection() }
    }

    private(set) var windowInfo: WindowInfo

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let appLabel = NSTextField(labelWithString: "")
    private let profileBadge = ProfileBadgeView()
    private let profileStripe = NSView()
    private let headerRow = NSStackView()
    private let size: CGFloat
    private let showThumbnail: Bool
    private let theme: SwitcherTheme

    init(window: WindowInfo, size: CGFloat, showThumbnail: Bool, theme: SwitcherTheme) {
        self.windowInfo = window
        self.size = size
        self.showThumbnail = showThumbnail
        self.theme = theme
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: Self.itemHeight(for: size)))
        setup()
        apply(window: window, isNewWindow: true)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: size, height: Self.itemHeight(for: size))
    }

    /// Refreshes labels and badge in place. The thumbnail is only reloaded when the view now
    /// represents a different window.
    func update(window: WindowInfo) {
        let isNewWindow = window.id != windowInfo.id
        windowInfo = window
        apply(window: window, isNewWindow: isNewWindow)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 2
        layer?.masksToBounds = true

        profileStripe.wantsLayer = true
        profileStripe.translatesAutoresizingMaskIntoConstraints = false

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 6
        imageView.layer?.masksToBounds = true
        imageView.layer?.backgroundColor = theme.thumbnailColor.cgColor

        appLabel.textColor = .labelColor
        appLabel.lineBreakMode = .byTruncatingTail
        appLabel.maximumNumberOfLines = 1
        appLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        profileBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        profileBadge.setContentHuggingPriority(.required, for: .horizontal)

        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(profileBadge)
        headerRow.addArrangedSubview(appLabel)

        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(profileStripe)
        addSubview(imageView)
        addSubview(headerRow)
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: Self.itemHeight(for: size)),
            profileStripe.leadingAnchor.constraint(equalTo: leadingAnchor),
            profileStripe.topAnchor.constraint(equalTo: topAnchor),
            profileStripe.bottomAnchor.constraint(equalTo: bottomAnchor),
            profileStripe.widthAnchor.constraint(equalToConstant: 5),
            headerRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            headerRow.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -7),
            headerRow.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            headerRow.heightAnchor.constraint(equalToConstant: 20),
            profileBadge.widthAnchor.constraint(lessThanOrEqualToConstant: max(60, size * 0.7)),
            titleLabel.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            titleLabel.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: 2),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            imageView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            imageView.heightAnchor.constraint(equalToConstant: Self.thumbnailHeight(for: size))
        ])
    }

    private func apply(window: WindowInfo, isNewWindow: Bool) {
        let profileColor = window.profileName.map(ProfilePalette.color(for:))

        // With a profile the badge is the headline and the app name steps back; without one the
        // app name keeps its usual weight.
        appLabel.stringValue = window.ownerName
        appLabel.font = .systemFont(ofSize: profileColor == nil ? 16 : 12, weight: .semibold)
        appLabel.textColor = profileColor == nil ? .labelColor : .secondaryLabelColor

        profileBadge.isHidden = profileColor == nil
        if let profileName = window.profileName, let profileColor {
            profileBadge.configure(text: profileName, color: profileColor)
        }
        profileStripe.isHidden = profileColor == nil
        profileStripe.layer?.backgroundColor = profileColor?.cgColor

        titleLabel.stringValue = Self.displayTitle(window.title)
        titleLabel.toolTip = window.title

        if isNewWindow {
            imageView.image = window.appIcon
            if showThumbnail {
                loadThumbnail()
            }
        }
        updateSelection()
    }

    /// Chrome repeats the browser and profile in its title; the badge already shows those.
    private static func displayTitle(_ title: String) -> String {
        let segments = title.components(separatedBy: " - ")
        guard segments.count >= 2,
              let browserIndex = segments.lastIndex(where: { segment in
                  ["Google Chrome", "Chromium", "Microsoft Edge", "Brave"].contains { segment.hasPrefix($0) }
              }),
              browserIndex > 0 else { return title }
        return segments[..<browserIndex].joined(separator: " - ")
    }

    private func updateSelection() {
        let profileColor = windowInfo.profileName.map(ProfilePalette.color(for:))
        layer?.borderColor = isSelected ? theme.accentColor.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = isSelected ? 3 : 2
        let restingColor = profileColor?.withAlphaComponent(0.16) ?? theme.cardColor
        layer?.backgroundColor = (isSelected ? theme.accentColor.withAlphaComponent(0.55) : restingColor).cgColor
        imageView.layer?.borderWidth = isSelected ? 1 : 0
        imageView.layer?.borderColor = theme.accentColor.cgColor
    }

    /// The cached thumbnail (or the app icon) is shown at once; a fresh capture replaces it when
    /// the WindowServer delivers one, so building the panel never waits on screen capture.
    private func loadThumbnail() {
        let windowID = windowInfo.id
        let cache = ThumbnailCache.shared
        if let cached = cache.cachedImage(for: windowID) {
            imageView.image = cached
        }
        cache.refresh(windowID: windowID, maxAge: Self.thumbnailMaxAge) { [weak self] image in
            guard let self, self.windowInfo.id == windowID else { return }
            self.imageView.image = image
        }
    }
}

/// A solid, coloured pill with the profile name in it.
final class ProfileBadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true

        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, color: NSColor) {
        label.stringValue = text
        layer?.backgroundColor = color.cgColor
    }
}
