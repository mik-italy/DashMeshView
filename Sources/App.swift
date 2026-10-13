import SwiftUI
import WebKit
import KSPlayer

@main
struct DashMeshApp: App {
    init() {
        // Inizializza i parametri del motore KSPlayer/FFmpeg
        KSOptions.firstPlayerType = KSMEPlayer.self
        KSOptions.secondPlayerType = KSMEPlayer.self
        KSOptions.isAutoPlay = true
    }

    var body: some Scene {
        WindowGroup {
            MainContentView()
        }
    }
}

struct ConfigResponse: Decodable {
    let url: String
    let useragent: String?
}

struct MainContentView: View {
    @State private var targetURL: URL? = nil
    @State private var appliedUA: String = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:149.0) Gecko/20100101 Firefox/149.0"
    @State private var isLoading = true
    @State private var activeStreamURL: URL? = nil
    @State private var showVideoPlayer = false
    @State private var logMessage: String = "Inizializzazione..."

    private let configEndpoint = URL(string: "https://api.globaltv.re/config")!

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Header superiore
                HStack {
                    Text("DashMeshView")
                        .font(.footnote).bold()
                    Spacer()
                    if activeStreamURL != nil {
                        Button(action: { showVideoPlayer.toggle() }) {
                            Label(showVideoPlayer ? "Portale" : "Video", systemImage: "play.rectangle.fill")
                                .font(.caption)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(Color(UIColor.secondarySystemBackground))

                // Portale Web con WebKit
                if let url = targetURL {
                    PortalWebView(
                        url: url,
                        userAgent: appliedUA,
                        onStreamIntercepted: { streamUri in
                            handleStreamIntercepted(streamUri)
                        }
                    )
                } else if isLoading {
                    ProgressView("Caricamento configurazione...")
                }

                // Barra informativa inferiore
                VStack(alignment: .leading, spacing: 2) {
                    Text("Stato:")
                        .font(.caption2).bold().foregroundColor(.yellow)
                    Text(logMessage)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.black.opacity(0.85))
                .foregroundColor(.white)
            }

            // Player KSPlayer a schermo intero
            if showVideoPlayer, let streamURL = activeStreamURL {
                ZStack(alignment: .topTrailing) {
                    KSPlayerRepresentable(url: streamURL, userAgent: appliedUA)
                        .edgesIgnoringSafeArea(.all)
                        .background(Color.black)

                    Button(action: {
                        showVideoPlayer = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(20)
                    }
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            fetchPortalConfig()
        }
    }

    private func handleStreamIntercepted(_ rawUrlString: String) {
        guard let url = URL(string: rawUrlString) else { return }
        logMessage = "Stream intercettato! Avvio KSPlayer..."
        self.activeStreamURL = url
        self.showVideoPlayer = true
    }

    private func fetchPortalConfig() {
        isLoading = true
        var request = URLRequest(url: configEndpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.isLoading = false
                guard let data = data,
                      let decodedConfig = try? JSONDecoder().decode(ConfigResponse.self, from: data),
                      let validURL = URL(string: decodedConfig.url) else {
                    self.logMessage = "Errore decodifica configurazione."
                    return
                }

                if let ua = decodedConfig.useragent, !ua.isEmpty {
                    self.appliedUA = ua
                }
                self.targetURL = validURL
                self.logMessage = "Portale caricato. Effettua il login."
            }
        }.resume()
    }
}

// Wrapper SwiftUI per KSPlayer (con intestazioni User-Agent)
struct KSPlayerRepresentable: UIViewRepresentable {
    let url: URL
    let userAgent: String

    func makeUIView(context: Context) -> IOSVideoPlayerView {
        let playerView = IOSVideoPlayerView()
        
        let opt = KSOptions()
        // Inietta lo User-Agent desktop richiesto direttamente nel motore FFmpeg
        opt.appendHeader(["User-Agent": userAgent])
        
        let resource = KSPlayerResource(url: url, options: opt)
        playerView.set(resource: resource)
        return playerView
    }

    func updateUIView(_ uiView: IOSVideoPlayerView, context: Context) {}
}

// WebView per navigare il portale e agganciare Shaka Player
struct PortalWebView: UIViewRepresentable {
    let url: URL
    let userAgent: String
    var onStreamIntercepted: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onStreamIntercepted: onStreamIntercepted)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "streamHandler")

        let jsScript = """
        (function() {
            function report(uri) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.streamHandler) {
                    window.webkit.messageHandlers.streamHandler.postMessage(String(uri));
                }
            }

            function hookShaka() {
                if (window.shaka && window.shaka.Player && window.shaka.Player.prototype) {
                    var origLoad = window.shaka.Player.prototype.load;
                    window.shaka.Player.prototype.load = function(assetUri) {
                        report(assetUri);
                        return origLoad.apply(this, arguments);
                    };
                } else {
                    setTimeout(hookShaka, 250);
                }
            }
            hookShaka();
        })();
        """

        let userScript = WKUserScript(source: jsScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        config.allowsInlineMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKScriptMessageHandler {
        var onStreamIntercepted: ((String) -> Void)?

        init(onStreamIntercepted: ((String) -> Void)?) {
            self.onStreamIntercepted = onStreamIntercepted
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "streamHandler", let uri = message.body as? String {
                DispatchQueue.main.async {
                    self.onStreamIntercepted?(uri)
                }
            }
        }
    }
}
