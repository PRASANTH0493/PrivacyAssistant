//
//  PrivacyOverlayView.swift
//
//  The warning banner and the "Content hidden for privacy" shield, in one view.
//  Owned and driven by PrivacyAssistant. Touches pass through wherever nothing is drawn.
//

import UIKit

@MainActor
final class PrivacyOverlayView: UIView {

    // Edit these to change the wording or to localize.
    private static let warningTitle = String(localized: "Possible person viewing your screen")
    private static let warningMessage = String(localized: "Someone behind you may be able to see.")
    private static let hideTitle = String(localized: "Hide content")
    private static let dismissTitle = String(localized: "Dismiss")
    private static let shieldTitle = String(localized: "Content hidden for privacy")
    private static let shieldMessage = String(localized: "Everything is paused until you show it again.")
    private static let showTitle = String(localized: "Show content")

    private let banner = UIView()
    private let shield = UIView()
    private let bannerButtons = UIStackView()

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildBanner()
        buildShield() // added last, so it covers the banner
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported.") }

    // MARK: - API used by PrivacyAssistant

    func showWarning() {
        guard banner.isHidden else { return }
        UIAccessibility.post(notification: .announcement, argument: "\(Self.warningTitle). \(Self.warningMessage)")
        setHidden(false, banner)
    }

    func hideWarning() { setHidden(true, banner) }

    /// Touches fall through to the screen underneath, except on the banner and the shield.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    // MARK: - Banner

    private func buildBanner() {
        banner.isHidden = true
        banner.backgroundColor = Palette.amber
        banner.layer.cornerRadius = 28
        banner.layer.cornerCurve = .continuous
        banner.layer.shadowOpacity = 0.25
        banner.layer.shadowRadius = 16
        banner.layer.shadowOffset = CGSize(width: 0, height: 8)
        banner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(banner)

        let icon = UIImageView(image: UIImage(systemName: "exclamationmark",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .heavy)))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.backgroundColor = Palette.orange
        icon.layer.cornerRadius = 10
        icon.layer.cornerCurve = .continuous
        icon.isAccessibilityElement = false

        let title = Self.label(Self.warningTitle, .headline, Palette.navy)
        title.accessibilityTraits = .header
        let message = Self.label(Self.warningMessage, .subheadline, Palette.navy.withAlphaComponent(0.7))
        let texts = UIStackView(arrangedSubviews: [title, message])
        texts.axis = .vertical
        texts.spacing = 2
        let header = UIStackView(arrangedSubviews: [icon, texts])
        header.alignment = .top
        header.spacing = 12

        let hide = GradientButton(title: Self.hideTitle) { [weak self] in self?.showShield() }
        hide.accessibilityHint = String(localized: "Hides all content until you show it again.")

        var dismissStyle = UIButton.Configuration.filled()
        dismissStyle.title = Self.dismissTitle
        dismissStyle.baseBackgroundColor = UIColor.white.withAlphaComponent(0.9)
        dismissStyle.baseForegroundColor = Palette.navy
        dismissStyle.cornerStyle = .large
        dismissStyle.contentInsets = GradientButton.insets
        dismissStyle.titleTextAttributesTransformer = .init { var a = $0; a.font = .preferredFont(forTextStyle: .headline); return a }
        let dismiss = UIButton(configuration: dismissStyle, primaryAction: UIAction { [weak self] _ in self?.hideWarning() })
        dismiss.accessibilityHint = String(localized: "Closes this warning. Hidden content stays hidden.")

        bannerButtons.addArrangedSubview(hide)
        bannerButtons.addArrangedSubview(dismiss)
        bannerButtons.spacing = 12
        bannerButtons.distribution = .fillEqually
        // Stack the buttons at accessibility text sizes so labels never truncate.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: PrivacyOverlayView, _) in
            view.bannerButtons.axis = view.traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        }

        let content = UIStackView(arrangedSubviews: [header, bannerButtons])
        content.axis = .vertical
        content.spacing = 14
        Self.pin(content, in: banner, inset: 16)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            banner.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8),
            banner.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            banner.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    // MARK: - Shield

    private func showShield() {
        UIAccessibility.post(notification: .screenChanged, argument: shield)
        setHidden(false, shield)
    }

    private func buildShield() {
        shield.isHidden = true
        shield.overrideUserInterfaceStyle = .dark
        shield.accessibilityViewIsModal = true
        shield.translatesAutoresizingMaskIntoConstraints = false
        addSubview(shield)
        NSLayoutConstraint.activate([
            shield.topAnchor.constraint(equalTo: topAnchor),
            shield.bottomAnchor.constraint(equalTo: bottomAnchor),
            shield.leadingAnchor.constraint(equalTo: leadingAnchor),
            shield.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Blur plus a mostly opaque navy tint with soft colored glows: underlying content is unreadable.
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        Self.pin(blur, in: shield)
        let backdrop = GlowBackdrop()
        Self.pin(backdrop, in: shield)

        let card = UIView()
        card.backgroundColor = Palette.navyElevated.withAlphaComponent(0.92)
        card.layer.cornerRadius = 32
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.08).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        shield.addSubview(card)

        let icon = UIImageView(image: UIImage(systemName: "eye.slash.fill",
                                              withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)))
        icon.tintColor = .white
        icon.contentMode = .center
        icon.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        icon.layer.cornerRadius = 36
        icon.isAccessibilityElement = false
        let iconRow = UIStackView(arrangedSubviews: [icon])
        iconRow.axis = .vertical
        iconRow.alignment = .center

        let title = Self.label(Self.shieldTitle, .title3, .white, bold: true, centered: true)
        title.accessibilityTraits = .header
        let message = Self.label(Self.shieldMessage, .subheadline, UIColor.white.withAlphaComponent(0.65), centered: true)
        let show = GradientButton(title: Self.showTitle, systemImage: "eye.fill") { [weak self] in
            guard let self else { return }
            self.setHidden(true, self.shield)
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
        show.accessibilityHint = String(localized: "Reveals the hidden content.")

        let stack = UIStackView(arrangedSubviews: [iconRow, title, message, show])
        stack.axis = .vertical
        stack.spacing = 8
        stack.setCustomSpacing(16, after: iconRow)
        stack.setCustomSpacing(20, after: message)
        Self.pin(stack, in: card, inset: 24)

        // Card fills the width minus 24pt margins, but never exceeds 420pt.
        let fill = card.widthAnchor.constraint(equalTo: shield.widthAnchor, constant: -48)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            card.centerXAnchor.constraint(equalTo: shield.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: shield.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            fill
        ])
    }

    // MARK: - Helpers

    private func setHidden(_ hidden: Bool, _ target: UIView) {
        guard target.isHidden != hidden else { return }
        if window == nil || UIAccessibility.isReduceMotionEnabled {
            target.isHidden = hidden
        } else {
            UIView.transition(with: target, duration: 0.25, options: .transitionCrossDissolve) { target.isHidden = hidden }
        }
    }

    private static func label(_ text: String, _ style: UIFont.TextStyle, _ color: UIColor,
                              bold: Bool = false, centered: Bool = false) -> UILabel {
        let label = UILabel()
        label.text = text
        let base = UIFont.preferredFont(forTextStyle: style)
        label.font = bold ? UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(.traitBold) ?? base.fontDescriptor, size: base.pointSize) : base
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        if centered { label.textAlignment = .center }
        return label
    }

    private static func pin(_ child: UIView, in parent: UIView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(child)
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset)
        ])
    }
}

// MARK: - Supporting views

private enum Palette {
    static let navy = UIColor(red: 0.04, green: 0.06, blue: 0.13, alpha: 1)
    static let navyElevated = UIColor(red: 0.07, green: 0.09, blue: 0.17, alpha: 1)
    static let blue = UIColor(red: 0.12, green: 0.38, blue: 0.96, alpha: 1)
    static let purple = UIColor(red: 0.50, green: 0.35, blue: 0.96, alpha: 1)
    static let cyan = UIColor(red: 0.06, green: 0.70, blue: 0.90, alpha: 1)
    static let green = UIColor(red: 0.10, green: 0.62, blue: 0.40, alpha: 1)
    static let amber = UIColor(red: 1.0, green: 0.90, blue: 0.80, alpha: 1)
    static let orange = UIColor(red: 0.97, green: 0.40, blue: 0.10, alpha: 1)
}

/// Blue to purple to cyan button.
private final class GradientButton: UIButton {
    static let insets = NSDirectionalEdgeInsets(top: 14, leading: 20, bottom: 14, trailing: 20)
    private let gradient = CAGradientLayer()

    init(title: String, systemImage: String? = nil, action: @escaping @MainActor () -> Void) {
        super.init(frame: .zero)
        var style = UIButton.Configuration.plain()
        style.title = title
        style.image = systemImage.flatMap { UIImage(systemName: $0) }
        style.imagePadding = 8
        style.baseForegroundColor = .white
        style.contentInsets = Self.insets
        style.titleTextAttributesTransformer = .init { var a = $0; a.font = .preferredFont(forTextStyle: .headline); return a }
        configuration = style
        addAction(UIAction { _ in action() }, for: .touchUpInside)

        gradient.colors = [Palette.blue, Palette.purple, Palette.cyan].map(\.cgColor)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = 18
        gradient.cornerCurve = .continuous
        layer.insertSublayer(gradient, at: 0)
        layer.shadowColor = Palette.purple.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 14
        layer.shadowOffset = CGSize(width: 0, height: 6)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported.") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
    }

    override var isHighlighted: Bool {
        didSet { transform = isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity }
    }
}

/// Mostly opaque navy with four soft glows, as in the shield design.
private final class GlowBackdrop: UIView {
    private let glows: [(layer: CAGradientLayer, x: CGFloat, y: CGFloat, size: CGFloat)]

    init() {
        func glow(_ color: UIColor) -> CAGradientLayer {
            let layer = CAGradientLayer()
            layer.type = .radial
            layer.colors = [color.withAlphaComponent(0.30).cgColor, color.withAlphaComponent(0).cgColor]
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            return layer
        }
        glows = [(glow(Palette.blue), 0.15, 0.18, 0.9), (glow(Palette.purple), 0.9, 0.42, 0.8),
                 (glow(Palette.green), 0.25, 0.82, 0.8), (glow(Palette.cyan), 0.95, 0.92, 0.6)]
        super.init(frame: .zero)
        backgroundColor = Palette.navy.withAlphaComponent(0.94)
        glows.forEach { layer.addSublayer($0.layer) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported.") }

    override func layoutSubviews() {
        super.layoutSubviews()
        for glow in glows {
            let side = bounds.width * glow.size * 1.6
            glow.layer.frame = CGRect(x: bounds.width * glow.x - side / 2, y: bounds.height * glow.y - side / 2, width: side, height: side)
        }
    }
}
