import Foundation

/// WAN IP, fetched ONLY when the panel opens, cached 5 minutes.
/// Structurally never runs in the background: the only caller is PanelView's .task,
/// which is cancelled when the panel closes.
actor PublicIPService {
    private var cached: (ip: String, at: Date)?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        return URLSession(configuration: config)
    }()

    func fetch() async -> String? {
        if let cached, Date().timeIntervalSince(cached.at) < 300 {
            return cached.ip
        }
        guard let url = URL(string: "https://api.ipify.org") else { return cached?.ip }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              Self.looksLikeIP(text) else {
            return cached?.ip  // stale beats blank; nil only if never fetched
        }
        cached = (text, Date())
        return text
    }

    /// A 200 with a plausible body is not success; assert the shape (IPv4 or IPv6 literal).
    private static func looksLikeIP(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 45 else { return false }
        return s.allSatisfy { $0.isHexDigit || $0 == "." || $0 == ":" }
    }
}
