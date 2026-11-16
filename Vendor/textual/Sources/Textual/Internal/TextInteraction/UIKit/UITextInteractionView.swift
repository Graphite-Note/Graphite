#if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(UIKit)
  import SwiftUI
  import os
  import UniformTypeIdentifiers

  // MARK: - Overview
  //
  // `UITextInteractionView` implements selection and link interaction on iOS-family platforms.
  //
  // The view sits in an overlay above one or more rendered `Text` fragments. It uses
  // `TextSelectionModel` to translate touch locations into URLs and selection ranges, and it
  // respects `exclusionRects` so embedded scrollable regions can continue to handle gestures.
  // Selection UI is provided by `UITextInteraction` configured for non-editable content.

  final class UITextInteractionView: UIView {
    override var canBecomeFirstResponder: Bool {
      true
    }

    var model: TextSelectionModel
    var exclusionRects: [CGRect]
    var openURL: OpenURLAction
    /// Graphite addition: told when the pointer or Apple Pencil comes onto a link and leaves
    /// it, and when a link is held; while nil, the view follows neither.
    var linkHoverAction: TextLinkHoverAction? {
      didSet {
        linkHoverGesture.isEnabled = linkHoverAction != nil
        linkPressGesture.isEnabled = linkHoverAction != nil || linkInteractions != nil
      }
    }
    /// Graphite addition: a host's own menu for some links, shown by a long press or a
    /// secondary click on them, and what a tap with modifier keys on a link does.
    var linkInteractions: TextLinkInteractions? {
      didSet {
        linkPressGesture.isEnabled = linkHoverAction != nil || linkInteractions != nil
        linkSecondaryClickGesture.isEnabled = linkInteractions != nil
      }
    }

    weak var inputDelegate: (any UITextInputDelegate)?

    let logger = Logger(category: .textInteraction)

    private(set) lazy var _tokenizer = UITextInputStringTokenizer(textInput: self)
    private let selectionInteraction: UITextInteraction
    private lazy var linkHoverGesture = UIHoverGestureRecognizer(target: self, action: #selector(handleLinkHover(_:)))
    private lazy var linkPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLinkPress(_:)))
    private lazy var linkSecondaryClickGesture: UITapGestureRecognizer = {
      let gesture = UITapGestureRecognizer(target: self, action: #selector(handleLinkSecondaryClick(_:)))
      gesture.buttonMaskRequired = .secondary
      return gesture
    }()
    /// Shows a link's own menu; made the first time one is shown.
    private var linkMenuInteraction: UIEditMenuInteraction?
    /// The items of the link menu being shown.
    private var shownLinkMenuItems: [TextLinkMenuItem] = []
    private var hoveredLinkURL: URL?

    init(
      model: TextSelectionModel,
      exclusionRects: [CGRect],
      openURL: OpenURLAction
    ) {
      self.model = model
      self.exclusionRects = exclusionRects
      self.openURL = openURL
      self.selectionInteraction = UITextInteraction(for: .nonEditable)

      super.init(frame: .zero)
      self.backgroundColor = .clear

      setUp()
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
      for exclusionRect in exclusionRects {
        if exclusionRect.contains(point) {
          return false
        }
      }
      return super.point(inside: point, with: event)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
      switch action {
      case #selector(copy(_:)), #selector(share(_:)):
        return !(model.selectedRange?.isCollapsed ?? true)
      default:
        return false
      }
    }

    override func copy(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let formatter = Formatter(attributedText)

      UIPasteboard.general.setItems(
        [
          [
            UTType.plainText.identifier: formatter.plainText(),
            UTType.html.identifier: formatter.html(),
          ]
        ]
      )
    }

    private func setUp() {
      model.selectionWillChange = { [weak self] in
        guard let self else { return }
        self.inputDelegate?.selectionWillChange(self)
      }
      model.selectionDidChange = { [weak self] in
        guard let self else { return }
        self.inputDelegate?.selectionDidChange(self)
      }

      let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
      addGestureRecognizer(tapGesture)

      selectionInteraction.textInput = self
      selectionInteraction.delegate = self

      for gesture in selectionInteraction.gesturesForFailureRequirements {
        tapGesture.require(toFail: gesture)
      }

      addInteraction(selectionInteraction)

      linkHoverGesture.isEnabled = false
      addGestureRecognizer(linkHoverGesture)
      // A link held shows its preview instead of selecting its word; the selection's gestures
      // wait for this one only while a touch starts on a link (`shouldReceive`).
      linkPressGesture.isEnabled = false
      linkPressGesture.delegate = self
      for gesture in selectionInteraction.gesturesForFailureRequirements {
        gesture.require(toFail: linkPressGesture)
      }
      addGestureRecognizer(linkPressGesture)
      linkSecondaryClickGesture.isEnabled = false
      linkSecondaryClickGesture.delegate = self
      addGestureRecognizer(linkSecondaryClickGesture)
    }

    /// Reports the link under the pointer when the pointer came onto it, and the link it left;
    /// moving between the lines of one link is staying on it.
    @objc private func handleLinkHover(_ gesture: UIHoverGestureRecognizer) {
      guard let linkHoverAction else { return }
      let isHovering = gesture.state == .began || gesture.state == .changed
      let link = isHovering ? model.link(for: gesture.location(in: self)) : nil
      guard link?.url != hoveredLinkURL else { return }
      if let hoveredLinkURL {
        linkHoverAction(.exited(hoveredLinkURL))
      }
      hoveredLinkURL = link?.url
      if let link {
        linkHoverAction(.entered(link.url, frame: convert(link.frame, to: nil)))
      }
    }

    @objc private func handleLinkPress(_ gesture: UILongPressGestureRecognizer) {
      guard gesture.state == .began, let link = model.link(for: gesture.location(in: self)) else { return }
      if showLinkMenu(for: link.url, at: gesture.location(in: self)) { return }
      linkHoverAction?(.pressed(link.url, frame: convert(link.frame, to: nil)))
    }

    @objc private func handleLinkSecondaryClick(_ gesture: UITapGestureRecognizer) {
      let location = gesture.location(in: self)
      guard let url = model.url(for: location) else { return }
      _ = showLinkMenu(for: url, at: location)
    }

    /// Shows the host's own menu for the link to `url`, as the system's edit menu at
    /// `location`; false when the host has none for it.
    private func showLinkMenu(for url: URL, at location: CGPoint) -> Bool {
      guard let items = linkInteractions?.menuItems(url), !items.isEmpty else { return false }
      shownLinkMenuItems = items
      let interaction = linkMenuInteraction ?? UIEditMenuInteraction(delegate: self)
      if linkMenuInteraction == nil {
        addInteraction(interaction)
        linkMenuInteraction = interaction
      }
      interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: location))
      return true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
      let location = gesture.location(in: self)
      guard let url = model.url(for: location) else {
        model.selectedRange = nil
        return
      }
      let modifiers = gesture.modifierFlags.eventModifiers
      if !modifiers.isEmpty, linkInteractions?.openWithModifiers(url, modifiers) == true { return }
      openURL(url)
    }

    @objc private func share(_ sender: Any?) {
      guard let selectedRange = model.selectedRange else {
        return
      }

      let attributedText = model.attributedText(in: selectedRange)
      let itemSource = TextActivityItemSource(attributedString: attributedText)

      let activityViewController = UIActivityViewController(
        activityItems: [itemSource],
        applicationActivities: nil
      )

      if let popover = activityViewController.popoverPresentationController {
        let rect =
          model.selectionRects(for: selectedRange)
          .last?.rect.integral ?? .zero
        popover.sourceView = self
        popover.sourceRect = rect
      }

      if let windowScene = window?.windowScene,
        let viewController = windowScene.windows.first?.rootViewController
      {
        viewController.present(activityViewController, animated: true)
      }
    }
  }

  extension UITextInteractionView: UIGestureRecognizerDelegate {
    /// The press on links takes only touches that start on a link, so elsewhere the selection
    /// does not wait for it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
      if gestureRecognizer === linkSecondaryClickGesture {
        return hasLinkMenu(at: touch.location(in: self))
      }
      guard gestureRecognizer === linkPressGesture else { return true }
      guard let link = model.link(for: touch.location(in: self)) else { return false }
      return linkHoverAction != nil || !(linkInteractions?.menuItems(link.url).isEmpty ?? true)
    }

    private func hasLinkMenu(at location: CGPoint) -> Bool {
      guard let linkInteractions, let url = model.url(for: location) else { return false }
      return !linkInteractions.menuItems(url).isEmpty
    }
  }

  extension UITextInteractionView: @MainActor UIEditMenuInteractionDelegate {
    /// Graphite addition: a link's own menu holds only the host's items.
    func editMenuInteraction(
      _ interaction: UIEditMenuInteraction,
      menuFor configuration: UIEditMenuConfiguration,
      suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
      UIMenu(children: shownLinkMenuItems.map { item in
        UIAction(title: item.title, image: UIImage(systemName: item.systemImage)) { _ in item.action() }
      })
    }
  }

  extension UITextInteractionView: UITextInteractionDelegate {
    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool {
      logger.debug("interactionShouldBegin(at: \(point.logDescription)) -> true")
      return true
    }

    func interactionWillBegin(_ interaction: UITextInteraction) {
      logger.debug("interactionWillBegin")
      _ = self.becomeFirstResponder()
    }

    func interactionDidEnd(_ interaction: UITextInteraction) {
      logger.debug("interactionDidEnd")
    }
  }

  extension Logger.Textual.Category {
    fileprivate static let textInteraction = Self(rawValue: "textInteraction")
  }
#endif
