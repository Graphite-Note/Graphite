/**
 * File: FloatingSelectionToolbar.swift
 * ------------------------------------
 * Layer: UI
 * Description: The floating toolbar beside a selection on the iPad and the iPhone, a selected PDF picture or the
 *              lasso's selection: a dark capsule of SF Symbols, a destructive one in red, the rest behind "…", placed
 *              below the selection, or above it where there is no room, inside what its host view shows.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import UIKit

/// One command of a floating toolbar.
struct FloatingToolbarItem {
    /// Its VoiceOver label, pointer tooltip and large-content title, and its title in the "…" menu.
    let title: String
    let systemImageName: String
    /// Drawn as the symbol's own colour, as a colour swatch ("circle.fill") is; nil draws it as the bar's symbols.
    var symbolColor: UIColor?
    var isEnabled = true
    var isDestructive = false
    /// Whether it is in the "…" menu rather than on the bar.
    var isInMoreMenu = false
    /// Items of different groups are parted by a thin line on the bar.
    var group = 0
    let action: () -> Void
}

/// A capsule of icon buttons beside a selection. Its host is a view that is not scaled (a PDF
/// view, a window), so the bar keeps its size on screen however far a page is zoomed; a rect of
/// a scaled view is converted to the host first (`show(_:moreMenuElements:pointingAt:of:in:)`).
/// Nothing is made until a selection first shows it.
@MainActor
final class FloatingSelectionToolbar: UIView {
    static let barHeight: CGFloat = 44
    /// Space between the selection and the bar.
    static let gap: CGFloat = 10
    /// Space kept between the bar and the edges of what the host shows.
    static let margin: CGFloat = 8
    private static let buttonWidth: CGFloat = 44
    private static let dividerWidth: CGFloat = 1

    private let background = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterialDark))
    private let stack = UIStackView()
    /// The items the bar shows, as given, and their buttons in order, for tests.
    private(set) var items: [FloatingToolbarItem] = []
    private(set) var buttons: [UIButton] = []
    /// The "…" button, when some items are in its menu.
    private(set) var moreButton: UIButton?
    /// The selection's box in the host, which the bar stands beside.
    private(set) var targetRect: CGRect = .null
    /// Whether the bar stands above the selection, where there was no room below it.
    private(set) var standsAbove = false

    var isShown: Bool { superview != nil && !isHidden && alpha > 0 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 3)
        background.clipsToBounds = true
        background.layer.cornerCurve = .continuous
        background.layer.cornerRadius = Self.barHeight / 2
        background.overrideUserInterfaceStyle = .dark
        addSubview(background)
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        // The capsule's round ends stand a little away from the first and last symbols.
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6)
        background.contentView.addSubview(stack)
        // A held finger shows a button's large title when text is large, as a bar's buttons do.
        addInteraction(UILargeContentViewerInteraction())
        accessibilityContainerType = .semanticGroup
        accessibilityLabel = "Selection"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Showing

    /// Shows `items` beside `targetRect`, a rectangle of `host`, adding the bar to `host`.
    func show(_ items: [FloatingToolbarItem], moreMenuElements: [UIMenuElement] = [], pointingAt targetRect: CGRect, in host: UIView) {
        if superview !== host { host.addSubview(self) }
        host.bringSubviewToFront(self)
        rebuild(items, moreMenuElements: moreMenuElements)
        follow(targetRect)
        guard isHidden || alpha < 1 else { return }
        isHidden = false
        if UIAccessibility.isReduceMotionEnabled {
            alpha = 0
            UIView.animate(withDuration: 0.15) { self.alpha = 1 }
        } else {
            alpha = 0
            transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                self.alpha = 1
                self.transform = .identity
            }
        }
    }

    /// Shows the bar beside a rectangle of `view`, which may be scaled (a canvas on a zoomed page), in `host`, which is not.
    func show(_ items: [FloatingToolbarItem], moreMenuElements: [UIMenuElement] = [], pointingAt rect: CGRect, of view: UIView, in host: UIView) {
        show(items, moreMenuElements: moreMenuElements, pointingAt: view.convert(rect, to: host), in: host)
    }

    /// Places the bar again beside the selection, which moved (scrolling, zooming, a change).
    func follow(_ targetRect: CGRect) {
        guard let host = superview else { return }
        self.targetRect = targetRect
        let size = CGSize(width: stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width, height: Self.barHeight)
        let placement = Self.placement(ofBarSized: size, beside: targetRect, within: host.bounds.inset(by: host.safeAreaInsets))
        standsAbove = placement.standsAbove
        bounds = CGRect(origin: .zero, size: size)
        center = CGPoint(x: placement.origin.x + size.width / 2, y: placement.origin.y + size.height / 2)
        background.frame = bounds
        stack.frame = bounds
        // The buttons stand in their places at once, so a touch or a test that comes before
        // the next layout pass finds them, not the stack behind them.
        stack.layoutIfNeeded()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: Self.barHeight / 2).cgPath
    }

    func hide() {
        guard !isHidden else { return }
        isHidden = true
        alpha = 0
    }

    /// Where a bar of `size` stands beside `target`: centred under it, or over it where there
    /// is no room below, moved sideways and up or down to stay `margin` inside `region`.
    static func placement(ofBarSized size: CGSize, beside target: CGRect, within region: CGRect) -> (origin: CGPoint, standsAbove: Bool) {
        let inner = region.insetBy(dx: margin, dy: margin)
        let x = kept(target.midX - size.width / 2, between: inner.minX, and: inner.maxX - size.width)
        let below = target.maxY + gap, above = target.minY - gap - size.height
        if below + size.height <= inner.maxY { return (CGPoint(x: x, y: max(below, inner.minY)), false) }
        if above >= inner.minY { return (CGPoint(x: x, y: min(above, inner.maxY - size.height)), true) }
        // A selection taller than what is shown: the bar stands inside it, at the bottom of what is shown.
        return (CGPoint(x: x, y: kept(inner.maxY - size.height, between: inner.minY, and: inner.maxY - size.height)), false)
    }

    private static func kept(_ value: CGFloat, between lowest: CGFloat, and highest: CGFloat) -> CGFloat {
        guard lowest <= highest else { return (lowest + highest) / 2 }
        return min(max(value, lowest), highest)
    }

    /// Whether a view is in a floating toolbar, so a tap on the bar is not also a tap on what is under it.
    static func contains(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is FloatingSelectionToolbar { return true }
            current = candidate.superview
        }
        return false
    }

    // MARK: Buttons

    private func rebuild(_ items: [FloatingToolbarItem], moreMenuElements: [UIMenuElement]) {
        self.items = items
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        buttons = []
        moreButton = nil
        let onBar = items.filter { item in !item.isInMoreMenu }
        var previousGroup = onBar.first?.group
        for item in onBar {
            if item.group != previousGroup { stack.addArrangedSubview(Self.makeDivider()) }
            previousGroup = item.group
            let button = Self.makeButton(title: item.title, systemImageName: item.systemImageName, symbolColor: item.symbolColor,
                                         isDestructive: item.isDestructive)
            button.isEnabled = item.isEnabled
            button.alpha = item.isEnabled ? 1 : 0.35
            button.addAction(UIAction { _ in item.action() }, for: .primaryActionTriggered)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }
        let inMenu = items.filter(\.isInMoreMenu)
        guard !inMenu.isEmpty || !moreMenuElements.isEmpty else { return }
        if !onBar.isEmpty { stack.addArrangedSubview(Self.makeDivider()) }
        let more = Self.makeButton(title: "More", systemImageName: "ellipsis.circle", symbolColor: nil, isDestructive: false)
        more.menu = UIMenu(children: inMenu.map(Self.menuAction(of:)) + moreMenuElements)
        more.showsMenuAsPrimaryAction = true
        stack.addArrangedSubview(more)
        moreButton = more
    }

    static func menuAction(of item: FloatingToolbarItem) -> UIAction {
        var attributes: UIMenuElement.Attributes = []
        if !item.isEnabled { attributes.insert(.disabled) }
        if item.isDestructive { attributes.insert(.destructive) }
        let image = UIImage(systemName: item.systemImageName).map { image in
            item.symbolColor.map { color in image.withTintColor(color, renderingMode: .alwaysOriginal) } ?? image
        }
        return UIAction(title: item.title, image: image, attributes: attributes) { _ in item.action() }
    }

    private static func makeButton(title: String, systemImageName: String, symbolColor: UIColor?, isDestructive: Bool) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        let symbol = UIImage(systemName: systemImageName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        configuration.image = symbolColor.flatMap { color in symbol?.withTintColor(color, renderingMode: .alwaysOriginal) } ?? symbol
        configuration.baseForegroundColor = isDestructive ? .systemRed : .white
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        button.largeContentTitle = title
        button.showsLargeContentViewer = true
        button.toolTip = title
        button.isPointerInteractionEnabled = true
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: buttonWidth),
                                     button.heightAnchor.constraint(equalToConstant: barHeight)])
        return button
    }

    private static func makeDivider() -> UIView {
        let divider = UIView()
        divider.backgroundColor = UIColor.white.withAlphaComponent(0.25)
        divider.isAccessibilityElement = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([divider.widthAnchor.constraint(equalToConstant: dividerWidth),
                                     divider.heightAnchor.constraint(equalToConstant: 24)])
        let holder = UIView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(divider)
        NSLayoutConstraint.activate([holder.widthAnchor.constraint(equalToConstant: dividerWidth + 8), holder.heightAnchor.constraint(equalToConstant: barHeight),
                                     divider.centerXAnchor.constraint(equalTo: holder.centerXAnchor), divider.centerYAnchor.constraint(equalTo: holder.centerYAnchor)])
        return holder
    }
}
#endif
