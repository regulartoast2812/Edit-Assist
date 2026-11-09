import AppKit
import SwiftUI
import WebKit

// Sage's mini player (2026-11-07, Windows-first in Creative Assist; brought back to the Mac 2026-11-09): any YouTube video
// plays in Sage from its thumbnail, docked in the corner or expanded over the stage.

extension Study {
    // MARK: The mini player (YouTube's own embed, hosted by a small local page so it has an origin and a referrer)

    /// The made-up host the player page says it comes from (a .example name: nothing is ever looked up there).
    static let playerHost = "sage-player.example"

    /// A video id YouTube could have made (letters, digits, - and _), so nothing else reaches the player's address.
    static func isVideoID(_ id: String?) -> Bool {
        guard let id, (6 ... 20).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_") }
    }

    /// The local player page's address for a video, or nil for something that is not a video id.
    static func playerURL(_ id: String) -> URL? { isVideoID(id) ? URL(string: "https://\(playerHost)/player.html?v=\(id)") : nil }

    /// YouTube's privacy-enhanced embed, as the player page loads it in its frame.
    static func embedURL(_ id: String) -> String {
        "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1&rel=0&modestbranding=1&playsinline=1&origin=https://\(playerHost)"
    }

    /// The player page: a black page holding YouTube's embed in an iframe. Loaded with its address as the base
    /// (https://sage-player.example/player.html?v=…), it has an origin and sends a referrer, which the embed needs (from
    /// about:blank or a page with no base it fails with "Error 153").
    static let playerPage = """
        <!doctype html><html><head><meta charset="utf-8"><meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%;display:block}</style></head>
        <body><script>
        var params = new URLSearchParams(location.search), id = params.get('v') || '';
        // A player laid over a note's card waits for your click on it (autoplay=0); the mini player starts at once.
        var auto = params.get('autoplay') === '0' ? '0' : '1';
        if (/^[A-Za-z0-9_-]{6,20}$/.test(id)) {
          var f = document.createElement('iframe');
          f.src = 'https://www.youtube-nocookie.com/embed/' + id + '?autoplay=' + auto + '&rel=0&modestbranding=1&playsinline=1&origin=' + encodeURIComponent(location.origin);
          f.allow = 'autoplay; encrypted-media; picture-in-picture; fullscreen; clipboard-write';
          f.referrerPolicy = 'strict-origin-when-cross-origin';
          f.allowFullscreen = true;
          document.body.appendChild(f);
        }
        </script></body></html>
        """
}

/// The player itself: YouTube's own embed in one web view, kept while the player is open (docked or expanded, the same
/// view, only resized). The embed needs an origin and a referrer, so the tiny page (`Study.playerPage`) is loaded with
/// https://sage-player.example/ as its address. Links out of the player open in your browser, never in the app; closing the
/// player takes the web view away, so nothing keeps playing.
struct SagePlayerWeb: NSViewRepresentable {
    let id: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // You pressed play in the app, which the page can't see as a press on itself.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.playing != id, let url = Study.playerURL(id) else { return }
        context.coordinator.playing = id
        view.loadHTMLString(Study.playerPage, baseURL: url)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var playing: String?

        /// The page itself only ever shows the player; anything else asked of the top page goes to your browser.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.targetFrame?.isMainFrame != false, let url = action.request.url else { decisionHandler(.allow); return }
            if url.host == Study.playerHost || url.scheme == "about" { decisionHandler(.allow); return }
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated { Self.open(url) }
        }

        /// "Watch on YouTube", the title, the channel: new windows open in your browser.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { Self.open(url) }
            return nil
        }

        static func open(_ url: URL) {
            if ["http", "https"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url) }
        }
    }
}
