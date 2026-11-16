import Foundation

/// A set of files Graphite downloads the first time they are needed instead of carrying them
/// inside the app, so the app stays small: pictures, sample content and other extras that a
/// feature can do without until they arrive. Every file is named with its size and SHA-256,
/// so a download that was cut short or changed on the way is never used, and the files come
/// from one fixed `revision`, so what a build downloads never changes under it. A pack can also
/// come with the app (`delivery`); Graphite's own download is then what a build without that copy uses.
public struct AddOnPack: Hashable, Sendable, Identifiable {
    /// A stable name for the pack, used as its folder's name on the device.
    public let id: String
    /// What the pack is, in the words Settings shows.
    public let title: String
    /// The version of the files, such as the commit they are downloaded from. A pack whose
    /// revision changes is downloaded again.
    public let revision: String
    /// The address each file's name is appended to.
    public let baseAddress: URL
    public let files: [AddOnFile]
    /// How the files reach the device besides Graphite's own download.
    public let delivery: AddOnPackDelivery

    public init(id: String, title: String, revision: String, baseAddress: URL, files: [AddOnFile], delivery: AddOnPackDelivery = .downloadOnly) {
        self.id = id
        self.title = title
        self.revision = revision
        self.baseAddress = baseAddress
        self.files = files
        self.delivery = delivery
    }

    /// The size of all the pack's files together, as downloaded and as kept on the device.
    public var byteCount: Int64 { files.reduce(0) { total, file in total + file.byteCount } }

    public func address(of file: AddOnFile) -> URL { baseAddress.appendingPathComponent(file.name) }

    public func file(named name: String) -> AddOnFile? { files.first { file in file.name == name } }
}

/// One file of an add-on pack: its name in the pack's folder, its size and its SHA-256.
public struct AddOnFile: Hashable, Sendable {
    public let name: String
    public let byteCount: Int64
    /// Lowercase hexadecimal.
    public let sha256: String

    public init(name: String, byteCount: Int64, sha256: String) {
        self.name = name
        self.byteCount = byteCount
        self.sha256 = sha256
    }
}

/// How an add-on pack's files reach the device besides Graphite's own download from `baseAddress`.
public enum AddOnPackDelivery: Hashable, Sendable {
    /// Only Graphite's own download, the first time a feature needs the files.
    case downloadOnly
    /// In the app's own bundle: installed with the app, and never removed while it is installed.
    case inAppBundle
    /// The files of this On-Demand Resources tag, one of the App Store's initial install tags: installed with the app,
    /// removable, and downloaded again by the system when asked for after it took their space back.
    case onDemandResourcesTag(String)
}

extension AddOnPackDelivery {
    /// Whether the files are in the app's own bundle.
    public var isInAppBundle: Bool {
        switch self {
        case .inAppBundle: true
        case .downloadOnly, .onDemandResourcesTag: false
        }
    }

    /// The On-Demand Resources tag the files come as, if they do.
    public var onDemandResourcesTag: String? {
        switch self {
        case .onDemandResourcesTag(let tag): tag
        case .downloadOnly, .inAppBundle: nil
        }
    }
}
