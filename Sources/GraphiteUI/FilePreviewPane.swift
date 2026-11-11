import SwiftUI
import QuickLook
import GraphiteCore
import GraphiteApple

#if canImport(UIKit)
typealias DecodedPlatformImage = UIImage
#else
typealias DecodedPlatformImage = NSImage
#endif

extension DecodedPlatformImage {
    /// Wraps pixels `ImageFileService.displayImage` has already decoded, at one image pixel
    /// per point, as the PNG data it replaces was read.
    convenience init(decodedImage: CGImage) {
        #if canImport(UIKit)
        self.init(cgImage: decodedImage)
        #else
        self.init(cgImage: decodedImage, size: CGSize(width: decodedImage.width, height: decodedImage.height))
        #endif
    }

    /// An image whose pixels are decoded away from the main thread on iOS. A plain
    /// `UIImage(data:)` decodes when it is first drawn, on the main thread: tens of
    /// milliseconds for a large photo.
    nonisolated static func preparedForDisplay(from imageData: Data) async -> sending DecodedPlatformImage? {
        guard let image = DecodedPlatformImage(data: imageData) else { return nil }
        #if canImport(UIKit)
        return await image.byPreparingForDisplay() ?? image
        #else
        return image
        #endif
    }
}

/// Shows an image or a Graphite drawing (PNG, PDF, or SVG) at full width.
struct ImagePane: View {
    let location: URL
    let path: VaultPath
    let drawingVersion: Int
    /// Whether this image's side of the split is focused; only then does the window's
    /// toolbar show its button.
    var isFocused = true
    let editDrawing: () -> Void
    /// Opens the drawing editor over a raster image; the result is saved beside it.
    var drawOnImage: (() -> Void)? = nil
    /// Decoded once per file content, so a toolbar change does not hand the zooming view a
    /// new image and reset its zoom.
    @State private var image: DecodedPlatformImage?
    /// The version of the file `image` was decoded from.
    @State private var imageFileVersion: ImageFileVersion?
    /// The file the state above belongs to. The pane is reused when another file opens in
    /// the same tab.
    @State private var loadedLocation: URL?
    @State private var hasEditableStrokes = false
    @State private var message: String?
    @State private var previewLocation: URL?

    var body: some View {
        imageContent
        .toolbar {
            #if canImport(UIKit)
            if hasEditableStrokes && isFocused {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit Drawing", systemImage: "pencil.tip.crop.circle") { editDrawing() }.tint(.primary)
                }
            } else if isFocused, image != nil, let drawOnImage {
                ToolbarItem(placement: .primaryAction) {
                    Button("Draw on Image", systemImage: "pencil.tip.crop.circle.badge.plus", action: drawOnImage).tint(.primary)
                }
            }
            #endif
        }
        .quickLookPreview($previewLocation)
        .task(id: "\(location.path)-\(drawingVersion)") {
            if loadedLocation != location {
                image = nil
                imageFileVersion = nil
                hasEditableStrokes = false
                message = nil
                loadedLocation = location
            }
            let content = await ImagePaneContent.load(from: location, fileExtension: path.fileExtension)
            guard !Task.isCancelled else { return }
            // A drawing version change after an unrelated external change leaves this file
            // as it was; keeping the same image keeps the user's zoom.
            if content.image == nil || content.fileVersion == nil || content.fileVersion != imageFileVersion {
                image = content.image.map(DecodedPlatformImage.init(decodedImage:))
                imageFileVersion = content.fileVersion
            }
            hasEditableStrokes = content.hasEditableStrokes
            message = content.message
        }
    }
}

/// The modification date and size of an image file, which tell a rewritten file from one
/// left as it was without comparing its pixels.
struct ImageFileVersion: Equatable, Sendable {
    let modificationDate: Date
    let byteCount: Int

    static func of(_ location: URL) -> ImageFileVersion? {
        guard let values = try? location.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modificationDate = values.contentModificationDate, let byteCount = values.fileSize else { return nil }
        return ImageFileVersion(modificationDate: modificationDate, byteCount: byteCount)
    }
}

/// What the image pane shows for one file.
struct ImagePaneContent: Sendable {
    /// Already decoded, off the main actor.
    var image: CGImage?
    /// The file's version before it was decoded; nil when it could not be read.
    var fileVersion: ImageFileVersion?
    var message: String?
    var hasEditableStrokes = false

    static let maximumPixelDimension = 2600

    static func load(from location: URL, fileExtension: String) async -> ImagePaneContent {
        var content = ImagePaneContent()
        content.fileVersion = await Task.detached(priority: .userInitiated) { ImageFileVersion.of(location) }.value
        do {
            content.image = try await ImageFileService().displayImage(at: location, maximumPixelDimension: maximumPixelDimension)
        } catch {
            content.message = error.localizedDescription
        }
        guard DrawingFormat(fileExtension: fileExtension) != nil else { return content }
        // Answered from the chunk headers for an ordinary PNG, so a photo is not read twice.
        let reading = await Task.detached(priority: .userInitiated) { DrawingMetadataReader.readMetadata(at: location) }.value
        content.hasEditableStrokes = reading?.payload != nil
        // An SVG changed in another app cannot be drawn at all; its own error says so, and
        // claiming the image is intact over an empty pane would be wrong.
        if reading?.metadataWasDiscarded == true, content.image != nil {
            content.message = "This drawing was changed in another app. The image is intact, but its Pencil strokes can no longer be edited."
        }
        return content
    }
}

extension ImagePane {
    @ViewBuilder private var imageContent: some View {
        #if canImport(UIKit)
        // Pinch and double-tap zoom, as in Photos.
        VStack(spacing: 0) {
            if let image {
                ZoomableImageView(image: image)
            } else if message == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
            if let message {
                Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                if image == nil {
                    Button("Preview") { previewLocation = location }.buttonStyle(.borderedProminent).padding(.bottom)
                }
            }
            if image == nil && message != nil { Spacer() }
        }
        #else
        // Pinch and double-click zoom, as in Preview.
        VStack(spacing: 20) {
            if let image, let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                MagnifyingImageView(image: picture)
            } else if message == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
            if let message { Text(message).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 32) }
            if image == nil && message != nil {
                Button("Preview") { previewLocation = location }.buttonStyle(.borderedProminent)
                Spacer()
            }
        }
        #endif
    }
}

#if canImport(UIKit)
/// An image that fits the view and zooms with a pinch, or to double size with a double tap.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    static let maximumZoomFactor: CGFloat = 8

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let scrollView = ZoomingImageScrollView()
        scrollView.image = image
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingImageScrollView, context: Context) {
        if scrollView.image !== image { scrollView.image = image }
    }
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var fittedBoundsSize: CGSize = .zero
    private static let margin: CGFloat = 24
    /// Runs on a single tap while the image is fitted, not zoomed in; nil does nothing. The
    /// zoom over a note closes with it, as Obsidian's does.
    var singleTapWhileFitted: (() -> Void)?

    var image: UIImage? {
        get { imageView.image }
        set {
            // The zoom is a scale transform on the image view; a frame set under it would
            // show the new image at that scale times its pixel size, and the layout below
            // would see an unchanged zoom and never fit it again.
            zoomScale = 1
            imageView.image = newValue
            imageView.frame = CGRect(origin: .zero, size: newValue?.size ?? .zero)
            contentSize = imageView.frame.size
            fittedBoundsSize = .zero
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        decelerationRate = .fast
        contentInsetAdjustmentBehavior = .never
        imageView.accessibilityIgnoresInvertColors = true
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)
    }

    @objc private func singleTapped() {
        guard zoomScale <= minimumZoomScale + 0.001 else { return }
        singleTapWhileFitted?()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let image, image.size.width > 0, image.size.height > 0, bounds.width > 0 else { return }
        if bounds.size != fittedBoundsSize {
            // Fit within the view, never enlarging a small image beyond its size.
            let availableSize = CGSize(width: max(bounds.width - 2 * Self.margin, 1), height: max(bounds.height - 2 * Self.margin, 1))
            let fittingScale = min(availableSize.width / image.size.width, availableSize.height / image.size.height, 1)
            let wasFitted = fittedBoundsSize == .zero || abs(zoomScale - minimumZoomScale) < 0.001
            minimumZoomScale = fittingScale
            maximumZoomScale = max(fittingScale * ZoomableImageView.maximumZoomFactor, 1)
            if wasFitted || zoomScale < fittingScale { zoomScale = fittingScale }
            fittedBoundsSize = bounds.size
        }
        centerImage()
    }

    /// Keeps a smaller-than-view image in the middle instead of the top-left corner.
    private func centerImage() {
        let horizontalInset = max((bounds.width - contentSize.width) / 2, 0)
        let verticalInset = max((bounds.height - contentSize.height) / 2, 0)
        contentInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    @objc private func toggleZoom(_ recognizer: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale + 0.001 {
            setZoomScale(minimumZoomScale, animated: !GraphiteMotion.isReduced)
        } else {
            let targetScale = min(minimumZoomScale * 2.5, maximumZoomScale)
            let point = recognizer.location(in: imageView)
            let size = CGSize(width: bounds.width / targetScale, height: bounds.height / targetScale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: !GraphiteMotion.isReduced)
        }
    }
}
#endif

struct FilePreviewPane: View {
    let location: URL
    @State private var previewLocation: URL?
    var body: some View {
        ContentUnavailableView {
            Label(location.lastPathComponent, systemImage: "doc")
        } description: { Text("Open this attachment with the system preview.") } actions: {
            Button("Preview") { previewLocation = location }.buttonStyle(.borderedProminent)
            ShareLink(item: location)
        }.quickLookPreview($previewLocation)
    }
}

/// Keeps the image last decoded from an embed's data. A note re-renders its embeds on many
/// changes, and a new image object would decode the whole bitmap again on the main thread.
@MainActor @Observable
final class DecodedImageCache {
    private var sourceData: Data?
    private var decodedImage: DecodedPlatformImage?

    /// The image last decoded, from the current data or from the data before it.
    var latestImage: DecodedPlatformImage? { decodedImage }

    /// Whether this data has been decoded, into an image or into nothing.
    func hasDecoded(_ imageData: Data) -> Bool {
        sourceData == imageData
    }

    /// Decodes the image away from the main thread, for drawing: a large photo takes tens
    /// of milliseconds to decode.
    func prepareImage(for imageData: Data) async {
        guard !hasDecoded(imageData) else { return }
        let preparedImage = await DecodedPlatformImage.preparedForDisplay(from: imageData)
        guard !Task.isCancelled else { return }
        sourceData = imageData
        decodedImage = preparedImage
    }

    /// Decodes on the calling thread when the image is needed at once, as for copying it.
    func image(for imageData: Data) -> DecodedPlatformImage? {
        if let sourceData, sourceData == imageData { return decodedImage }
        sourceData = imageData
        decodedImage = DecodedPlatformImage(data: imageData)
        return decodedImage
    }
}
