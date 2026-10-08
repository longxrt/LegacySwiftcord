//
//  WebView.swift
//  Swiftcord
//
//  Created by Vincent Kwok on 19/2/22.
//

import SwiftUI
import WebKit
import os

// MARK: Adapted from: https://stackoverflow.com/a/63055549/13409955

class WebViewModel: ObservableObject {
    @Published var link: String
    @Published var didFinishLoading: Bool = false
    @Published var token: String?
    @Published var pageTitle: String = ""

    init(link: String) {
        self.link = link
    }
}

struct WebView: NSViewRepresentable {
    let shrink: Bool
    let shrunkShowingQR: Bool

    public typealias NSViewType = WKWebView
    @EnvironmentObject var viewModel: WebViewModel

    private let webView: WKWebView = WKWebView()

    private func getB64Background(named name: String) -> String? {
        let image = NSImage(named: name)
        guard let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        let jpegData = bitmapRep.representation(using: .png, properties: [:])
        return jpegData?.base64EncodedString()
    }

    // If someone can split this into smaller chunks, I'm all open
    // swiftlint:disable:next function_body_length
    public func makeNSView(context: NSViewRepresentableContext<WebView>) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator as? WKUIDelegate
        webView.configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()

        let backgroundImageB64 = getB64Background(named: "LoginBackground")

        // swiftlint:disable indentation_width
        let interceptJS = """
        // Get rid of everything in localStorage for a fresh state
        localStorage.clear();
        // Keep a reference to the original localStorage and console.log
        // Discord overwrites/removes both
        let l = localStorage;
        let c = console.log;
        // Remove window localStorage object to allow overwriting it
        delete window.localStorage;

        // console.log wrapper with a tag
        const log = (o, s) => c('%c[LocalStorage Shim]%c', 'color:green;font-weight:700', '', o, s);

        // Set
        const s = (k, v) => {
          log('SET', k + ' <- ' + v);
          if (k === 'token') window.webkit.messageHandlers.tkEvt.postMessage(JSON.parse(v));
          l[k] = v
        }
        // Get
        const g = k => {
          log('GET', k + ' -> ' + l[k]);
          return l[k];
        }

        // Create a new localStorage object with a proxy
        window.localStorage = new Proxy({}, {
          get(target, name) {
            if (name === 'setItem') return s;
            if (name === 'getItem') return g;
            if (name === 'removeItem') return k => {
              log('DELETE', k);
              l.removeItem(k);
            }
            return g(name);
          },
          set(target, k, v) { s(k, v) }
        })

        // Also overwrite some styles
        window.onload = () => {
          // Remove the oversaturated background and fallback Discord logo
          document.querySelectorAll('#app-mount div[class^="characterBackground-"] > *:not(div)').forEach(e => e.remove());
          // Some things can only be styled thru a style since they are dynamically modified
          const s = document.createElement('style');
          s.innerHTML = `
            #app-mount {
              background: url(data:image/png;base64,\(backgroundImageB64 ?? ""));
              background-size: cover;
              background-position: center;
            }
            form[class*="authBox-"]::before, section[class*="authBox-"]::before {
              content: unset;
            }
            form[class*="authBox-"], section[class*="authBox-"]  {
              background-color: rgba(0, 0, 0, .7)!important;
              -webkit-backdrop-filter: blur(24px) saturate(140%);
              border-radius: \(shrink ? 0 : 12)px;
              \(shrink ? "padding: 1rem;" : "")
            }
            .theme-dark {
              --input-background: rgba(0, 0, 0, .25)!important;
            }
            div[class^="select-"] > div > div:nth-child(2) {
              background-color: var(--input-background)!important;
            }

            .qr-only div[class*="centeringWrapper-"]>div {
              flex-direction: column;
            }
            .qr-only div[class*="mainLoginContainer-"]>div:nth-child(2) {
              display: none;
            }
            .qr-only div[class*="qrLogin-"] {
              display: block!important;
              margin-top: 24px;
            }
          `;
          document.body.appendChild(s);
        }
        """
        // swiftlint:enable indentation_width
        webView.configuration.userContentController.addUserScript(WKUserScript(source: interceptJS, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView.configuration.userContentController.add(EvtHandler(viewModel), name: "tkEvt")
        #if DEBUG
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        #endif

        // Install the telemetry blocker before the first request so nothing slips through
        let link = viewModel.link
        LoginTelemetryBlocker.install(on: webView.configuration.userContentController) { [webView] in
            webView.load(URLRequest(url: URL(string: link)!))
        }
        return webView
    }

    public func updateNSView(_ nsView: WKWebView, context: NSViewRepresentableContext<WebView>) {
        nsView.evaluateJavaScript(
            shrunkShowingQR
            ? "document.body.classList.add('qr-only')"
            : "document.body.classList.remove('qr-only')"
        )
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel)
    }

    // Handles the event that's sent from injected JavaScript once the token is available
    class EvtHandler: NSObject, WKScriptMessageHandler {
        private var viewModel: WebViewModel

        init(_ viewModel: WebViewModel) {
            // Initialise the WebViewModel
            self.viewModel = viewModel
        }

        public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            viewModel.token = message.body as? String
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        private var viewModel: WebViewModel
        private let log = Logger(category: "WebViewCoordinator")

        init(_ viewModel: WebViewModel) {
            // Initialise the WebViewModel
            self.viewModel = viewModel
        }

        public func webView(_: WKWebView, didFail: WKNavigation!, withError: Error) { }

        public func webView(_: WKWebView, didFailProvisionalNavigation: WKNavigation!, withError: Error) { }

        // After the webpage is loaded, assign the data in WebViewModel class
        public func webView(_ web: WKWebView, didFinish: WKNavigation!) {
            self.viewModel.pageTitle = web.title!
            self.viewModel.link = web.url?.absoluteString ?? ""
            self.viewModel.didFinishLoading = true
            log.info("didFinishNavigation")
        }

        public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { }

        public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let decision: WKNavigationActionPolicy = navigationAction.request.url?.absoluteString == viewModel.link || navigationAction.request.url?.host == "newassets.hcaptcha.com" ? .allow : .cancel
            decisionHandler(decision)
            log.debug("Navigation to \(navigationAction.request.url?.absoluteString ?? "[unknown URL]", privacy: .public) \(decision == .allow ? "allowed" : "cancelled", privacy: .public)")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { }

        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

/// Blocks Discord's analytics, metrics and crash reporting on the login page.
///
/// Login uses Discord's own web app, which runs the same tracking as discord.com. The
/// Swiftcord client itself never calls these endpoints, so this only affects login.
private enum LoginTelemetryBlocker {
	private static let identifier = "swiftcord-login-telemetry-v1"
	private static let log = Logger(category: "LoginTelemetryBlocker")

	// WebKit's content rule regexes don't support alternation, so one rule per endpoint
	private static let rules = """
	[
	  {"trigger": {"url-filter": "^https?://[^/]*discord\\\\.com/api/v[0-9]+/science"}, "action": {"type": "block"}},
	  {"trigger": {"url-filter": "^https?://[^/]*discord\\\\.com/api/v[0-9]+/metrics"}, "action": {"type": "block"}},
	  {"trigger": {"url-filter": "^https?://[^/]*discord\\\\.com/api/v[0-9]+/track"}, "action": {"type": "block"}},
	  {"trigger": {"url-filter": "^https?://[^/]*discord\\\\.com/error-reporting-proxy/"}, "action": {"type": "block"}},
	  {"trigger": {"url-filter": "^https?://[^/]*sentry\\\\.io/"}, "action": {"type": "block"}}
	]
	"""

	/// Adds the rules to `controller`, then calls `completion` on the main thread.
	/// If the rules can't be compiled, login still proceeds.
	static func install(on controller: WKUserContentController, completion: @escaping () -> Void) {
		guard let store = WKContentRuleListStore.default() else {
			completion()
			return
		}
		store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) { list, error in
			DispatchQueue.main.async {
				if let list {
					controller.add(list)
				} else {
					log.error("Couldn't compile telemetry rules: \(String(describing: error), privacy: .public)")
				}
				completion()
			}
		}
	}
}
