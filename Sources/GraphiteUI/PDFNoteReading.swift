/**
 * File: PDFNoteReading.swift
 * --------------------------
 * Layer: UI
 * Description: Notes on the iPad: a tap with a finger or the pointer on a note's icon, made on the Mac, in Preview or in
 *              Acrobat, opens its text to read in a popover beside the icon, whether the PDF is being written on or read.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

#if canImport(UIKit)
import UIKit
import PDFKit
import GraphiteApple

/// Opens a note's text when its icon is tapped on a PDF page. Editing notes on the iPad is to be decided
/// (Docs/Mac-PDF-markup-todo.md, section 3); the Pencil keeps writing over a note, so only a finger or the pointer opens it.
@MainActor
final class PDFNoteReading: NSObject, UIGestureRecognizerDelegate {
    private weak var pdfView: PDFView?
    private weak var session: PDFSession?
    private(set) var tapRecognizer: UITapGestureRecognizer?
    /// The popover showing a note's text, while it is open.
    private(set) weak var shownReader: UIViewController?

    /// How far round an icon a fingertip still opens it, in points of the screen.
    private static let reachPoints: CGFloat = 8

    init(view: PDFView, session: PDFSession) {
        pdfView = view
        self.session = session
        super.init()
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.allowedTouchTypes = [UITouch.TouchType.direct, .indirectPointer].map { touchType in NSNumber(value: touchType.rawValue) }
        recognizer.delegate = self
        view.addGestureRecognizer(recognizer)
        tapRecognizer = recognizer
    }

    /// The note whose icon is under a point of the PDF view.
    func note(at viewPoint: CGPoint) -> (note: PDFNote, page: PDFPage)? {
        guard let pdfView, let session, let page = pdfView.page(for: viewPoint, nearest: false) else { return nil }
        let tolerance = Self.reachPoints / max(pdfView.scaleFactor, 0.01)
        guard let annotation = session.noteAnnotation(at: pdfView.convert(viewPoint, to: page), on: page, tolerance: tolerance),
              let note = PDFNote(annotation: annotation) else { return nil }
        return (note, page)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pdfView else { return false }
        return note(at: gestureRecognizer.location(in: pdfView)) != nil
    }

    /// A tap on a note is the note's alone: no other recognizer of the page (a mark's menu, the end of a selection) acts on it.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let pdfView, let found = note(at: recognizer.location(in: pdfView)) else { return }
        open(found.note, on: found.page)
    }

    /// Shows the note's text, read-only, in a popover pointing at its icon.
    func open(_ note: PDFNote, on page: PDFPage) {
        guard let pdfView, let presenter = Self.topmostController(from: pdfView.window?.rootViewController) else { return }
        let reader = PDFNoteReaderController(note: note)
        reader.modalPresentationStyle = .popover
        reader.preferredContentSize = CGSize(width: 280, height: 180)
        reader.popoverPresentationController?.sourceView = pdfView
        reader.popoverPresentationController?.sourceRect = pdfView.convert(note.iconBounds, from: page)
        reader.popoverPresentationController?.permittedArrowDirections = .any
        shownReader = reader
        presenter.present(reader, animated: !GraphiteMotion.isReduced)
    }

    private static func topmostController(from root: UIViewController?) -> UIViewController? {
        var controller = root
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed { controller = presented }
        return controller
    }
}

/// A note's text to read: its author when the file names one, above the text, which can be selected and copied.
final class PDFNoteReaderController: UIViewController {
    let note: PDFNote
    private(set) var textView: UITextView?

    init(note: PDFNote) {
        self.note = note
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let textView = UITextView()
        textView.isEditable = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        let author = note.author.map { name in name + "\n" } ?? ""
        let text = NSMutableAttributedString(string: author, attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1),
                                                                          .foregroundColor: UIColor.secondaryLabel])
        text.append(NSAttributedString(string: note.contents, attributes: [.font: UIFont.preferredFont(forTextStyle: .body),
                                                                            .foregroundColor: UIColor.label]))
        textView.attributedText = text
        textView.accessibilityLabel = "Note"
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        self.textView = textView
    }
}
#endif
