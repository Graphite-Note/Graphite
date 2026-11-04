import SwiftUI

// MARK: - Overview
//
// Attachments are stored in attributed content as a `Textual.Attachment` attribute, but SwiftUI
// `Text` can’t embed arbitrary views. The rendering pipeline converts these runs into placeholder
// `Text` segments and uses an overlay to draw the real views at the resolved layout positions.
//
// `AttachmentAttribute` is attached to the placeholder runs during `Text` construction. It carries:
// - the original attachment value (type-erased as `AnyAttachment`)
// - the run's `PresentationIntent` (used by formatters and higher-level rendering)
// - Graphite patch: for an attachment that hangs below the baseline, where it goes on its placeholder
//
// `Text.Layout.Run` exposes lightweight accessors so overlay code can discover attachments without
// reaching back into the original attributed string.

struct AttachmentAttribute: TextAttribute {
  var attachment: AnyAttachment
  var presentationIntent: PresentationIntent?
  var hangingPlacement: HangingAttachmentPlacement?

  init(
    _ attachment: AnyAttachment,
    presentationIntent: PresentationIntent?,
    hangingPlacement: HangingAttachmentPlacement?
  ) {
    self.attachment = attachment
    self.presentationIntent = presentationIntent
    self.hangingPlacement = hangingPlacement
  }
}

extension Text.Layout.Run {
  var attachment: AnyAttachment? {
    self[AttachmentAttribute.self]?.attachment
  }

  var attachmentPresentationIntent: PresentationIntent? {
    self[AttachmentAttribute.self]?.presentationIntent
  }

  /// Graphite patch: where this run's content is. It is the run's typographic bounds, except for
  /// an attachment that hangs below the baseline, which is not where its placeholder is.
  var contentBounds: CGRect {
    let bounds = typographicBounds.rect
    return self[AttachmentAttribute.self]?.hangingPlacement?.frame(onPlaceholderBounds: bounds) ?? bounds
  }
}
