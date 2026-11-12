/**
 * File: WebFramePage.swift
 * ------------------------
 * Layer: UI
 * Description: The live page of a note's web frame: a web view of its own with Graphite's frame data store, no access
 *              to the vault or the app, new windows in the browser, and how its loading went.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 12/11/2026
 */

import SwiftUI
import WebKit
import GraphiteCore

/// How a frame's page is loading.
enum WebFrameLoadState: Equatable {
    case loading
    case loaded
    /// The page could not be loaded, and why, in words for the person reading.
    case failed(String)
}

/// The web views of note frames (decision 5 of `Docs/Iframe-embeds-todo.md`). Each frame has a web view of its own, made
/// with nothing of the app's: no script message handler, no URL scheme handler, no user script and no file access, so a
/// page cannot reach the vault, Graphite or the community plugins' runtime (whose views have their own stores). Every
/// frame shares one website data store, Graphite's own, so a site keeps its cookies and settings as in a browser.
enum WebFrameWebViews {
    /// The frames' website data store's identifier, fixed so the store outlives a launch; never a plugin vault's.
    static let dataStoreIdentifier = UUID(uuid: (0x47, 0x52, 0x41, 0x50, 0x48, 0x49, 0x54, 0x45, 0x46, 0x52, 0x41, 0x4D, 0x45, 0x53, 0x00, 0x01))
    @MainActor static let dataStore = WKWebsiteDataStore(forIdentifier: dataStoreIdentifier)

    @MainActor static func configuration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        // Nothing plays until the person asks: no page of a note starts a sound by itself.
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        #if canImport(UIKit)
        // A video plays in its frame on the iPhone too, as in a browser's frame, rather than full screen.
        configuration.allowsInlineMediaPlayback = true
        #endif
        return configuration
    }

    @MainActor static func make() -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration())
        #if canImport(UIKit)
        // The frame sits in the note's column; the window's safe areas are the note's, not the page's.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        #endif
        return webView
    }

    /// The request that loads a frame's page: its address, with Graphite's identity as the HTTP `Referer`. A web view
    /// loading a page by itself sends none, and YouTube's player refuses to play without one (Error 153, "Video player
    /// configuration error"); YouTube asks an application that embeds it to send `https://` and its bundle identifier
    /// (YouTube API Services, Required Minimum Functionality). Only the application is named, never the note or the vault.
    static func request(for address: URL, bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> URLRequest {
        var request = URLRequest(url: address)
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            request.setValue("https://\(bundleIdentifier)/", forHTTPHeaderField: "Referer")
        }
        return request
    }

    /// Whether a page may go to `address` inside its frame. Only web pages: a vault file, a `file:` address or another
    /// app's scheme is refused, and a link to a web page that opens a new window goes to the browser instead
    /// (`WebFramePageController.webView(_:createWebViewWith:for:windowFeatures:)`).
    static func allowsNavigation(to address: URL?, isMainFrame: Bool) -> Bool {
        guard let scheme = address?.scheme?.lowercased() else { return false }
        if scheme == "http" || scheme == "https" { return true }
        // A page's own frames may hold a blank page, a script's document or one it made.
        return !isMainFrame && ["about", "blob", "data", "javascript"].contains(scheme)
    }

    /// What a failed load says, in words: offline, a site not found, or the system's own explanation.
    static func message(for error: any Error) -> String? {
        let nsError = error as NSError
        // A load replaced by another, or stopped because the frame left the screen, is not a failure.
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return nil }
        // WebKit's "frame load interrupted by policy change": a navigation the frame refused, or a download it does not start.
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return nil }
        guard nsError.domain == NSURLErrorDomain else { return couldNotLoad }
        switch nsError.code {
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorDataNotAllowed: return "You're offline."
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return "The site can't be found."
        case NSURLErrorCannotConnectToHost: return "The site isn't answering."
        case NSURLErrorTimedOut: return "The site took too long to answer."
        case NSURLErrorAppTransportSecurityRequiresSecureConnection: return "The page isn't on a secure (https) address."
        default: return couldNotLoad
        }
    }

    private static let couldNotLoad = "The page couldn't be loaded."
}

/// A frame's live page: its web view while it has one, how its loading went, and what the page may do. Kept by the
/// frame's view, so its state outlasts a web view given up off screen; the web view keeps it as its delegates.
@MainActor @Observable
final class WebFramePageController: NSObject {
    private(set) var loadState: WebFrameLoadState = .loading
    @ObservationIgnored private(set) weak var webView: WKWebView?
    @ObservationIgnored private var loadedAddress: URL?
    /// Opens a web page in the system browser, for a link the page opens in a new window.
    @ObservationIgnored var openExternally: (URL) -> Void = { _ in }

    /// Gives the controller a new web view, which loads `address`.
    func attach(_ webView: WKWebView, address: URL) {
        webView.navigationDelegate = self
        webView.uiDelegate = self
        self.webView = webView
        load(address)
    }

    /// Loads `address` when the web view shows another page's.
    func load(_ address: URL) {
        guard let webView, loadedAddress != address else { return }
        loadedAddress = address
        setLoadState(.loading)
        webView.load(WebFrameWebViews.request(for: address))
    }

    /// Loads the page again after a failure.
    func reload() {
        guard let address = loadedAddress else { return }
        loadedAddress = nil
        load(address)
    }

    /// Lets the web view go: its page stops and its web process can end.
    func detach(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        if self.webView === webView { self.webView = nil }
        loadedAddress = nil
    }

    private func setLoadState(_ state: WebFrameLoadState) {
        if loadState != state { loadState = state }
    }
}

extension WebFramePageController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        return WebFrameWebViews.allowsNavigation(to: navigationAction.request.url, isMainFrame: isMainFrame) ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
        // A link followed inside the frame shows its page once it has loaded; the frame keeps the page it shows meanwhile.
        if loadState != .loaded { setLoadState(.loading) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        setLoadState(.loaded)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation?, withError error: any Error) {
        if let message = WebFrameWebViews.message(for: error) { setLoadState(.failed(message)) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation?, withError error: any Error) {
        if let message = WebFrameWebViews.message(for: error) { setLoadState(.failed(message)) }
    }

    /// The system ends a page's web process when memory runs low; the frame says so and offers to load it again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        setLoadState(.failed("The page stopped."))
    }
}

extension WebFramePageController: WKUIDelegate {
    /// A link the page opens in a new window (`target="_blank"`, `window.open`) opens in the browser (decision 5).
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let address = navigationAction.request.url, let scheme = address.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            openExternally(address)
        }
        return nil
    }
}

/// Holds a frame's web view while it is in a window. A Live Preview block's view taken off screen into the pool of kept
/// views, or any view that leaves its window, gives its web view up at once, and makes a new one when it is back: the
/// web view and its web process are not kept for a page nobody sees. SwiftUI does not update a view out of a window, so
/// this is decided here, as the window changes, rather than in the frame's SwiftUI state.
final class WebFramePageContainer: WebFramePageContainerBase {
    let controller: WebFramePageController
    var address: URL {
        didSet { if address != oldValue { controller.load(address) } }
    }
    private(set) var webView: WKWebView?

    init(controller: WebFramePageController, address: URL) {
        self.controller = controller
        self.address = address
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("A frame's page is made in code.") }

    #if canImport(UIKit)
    override func didMoveToWindow() {
        super.didMoveToWindow()
        windowDidChange()
    }
    #else
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowDidChange()
    }
    #endif

    private func windowDidChange() {
        if window == nil {
            releaseWebView()
        } else if webView == nil {
            let webView = WebFrameWebViews.make()
            webView.frame = bounds
            #if canImport(UIKit)
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            #else
            webView.autoresizingMask = [.width, .height]
            #endif
            addSubview(webView)
            self.webView = webView
            controller.attach(webView, address: address)
        }
    }

    func releaseWebView() {
        guard let webView else { return }
        controller.detach(webView)
        webView.removeFromSuperview()
        self.webView = nil
    }
}

#if canImport(UIKit)
typealias WebFramePageContainerBase = UIView
#else
typealias WebFramePageContainerBase = NSView
#endif

/// The web view of a frame's page, sized by its frame (`WebFramePageContainer`).
struct WebFramePage {
    let address: URL
    let controller: WebFramePageController
    let openExternally: (URL) -> Void

    func makeCoordinator() -> WebFramePageController { controller }

    @MainActor private func makeContainer() -> WebFramePageContainer {
        controller.openExternally = openExternally
        return WebFramePageContainer(controller: controller, address: address)
    }
}

#if canImport(UIKit)
extension WebFramePage: UIViewRepresentable {
    func makeUIView(context: Context) -> WebFramePageContainer { makeContainer() }

    func updateUIView(_ container: WebFramePageContainer, context: Context) {
        container.address = address
    }

    static func dismantleUIView(_ container: WebFramePageContainer, coordinator: WebFramePageController) {
        container.releaseWebView()
    }
}
#else
extension WebFramePage: NSViewRepresentable {
    func makeNSView(context: Context) -> WebFramePageContainer { makeContainer() }

    func updateNSView(_ container: WebFramePageContainer, context: Context) {
        container.address = address
    }

    static func dismantleNSView(_ container: WebFramePageContainer, coordinator: WebFramePageController) {
        container.releaseWebView()
    }
}
#endif
