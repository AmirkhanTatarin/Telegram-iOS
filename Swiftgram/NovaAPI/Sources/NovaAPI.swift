import Foundation
import SGConfig

/// Novagram server (novagram-api on nl): speech-to-text and AI helpers.
/// URL and key come from sg_config at build time, never from the repository.
public enum NovaAPI {
    private static var baseURL: URL? {
        guard let string = SG_CONFIG.novaApiUrl, !string.isEmpty else {
            return nil
        }
        return URL(string: string)
    }

    private static var key: String {
        return SG_CONFIG.novaApiKey ?? ""
    }

    public static var isConfigured: Bool {
        return baseURL != nil && !key.isEmpty
    }

    public struct ChatLine {
        public let from: String
        public let text: String

        public init(from: String, text: String) {
            self.from = from
            self.text = text
        }
    }

    private static func request(path: String, body: Data, contentType: String, timeout: TimeInterval, completion: @escaping (String?) -> Void) -> URLSessionTask? {
        guard let url = baseURL?.appendingPathComponent(path) else {
            completion(nil)
            return nil
        }
        var urlRequest = URLRequest(url: url, timeoutInterval: timeout)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "X-Nova-Key")
        urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        let task = URLSession.shared.dataTask(with: urlRequest, completionHandler: { data, _, _ in
            var text: String?
            if let data = data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                text = object["text"] as? String
            }
            DispatchQueue.main.async {
                completion(text)
            }
        })
        task.resume()
        return task
    }

    /// Transcribes an audio file (m4a/aac) on the server.
    public static func transcribe(path: String, completion: @escaping (String?) -> Void) -> URLSessionTask? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            completion(nil)
            return nil
        }
        return request(path: "stt", body: data, contentType: "audio/mp4", timeout: 120.0, completion: completion)
    }

    /// mode: "reply" (answer as the user), "summary" (chat summary), "translate".
    public static func ai(mode: String, lines: [ChatLine], lang: String? = nil, hint: String? = nil, completion: @escaping (String?) -> Void) -> URLSessionTask? {
        var payload: [String: Any] = [
            "mode": mode,
            "messages": lines.map { ["from": $0.from, "text": $0.text] }
        ]
        if let lang = lang {
            payload["lang"] = lang
        }
        if let hint = hint {
            payload["hint"] = hint
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(nil)
            return nil
        }
        return request(path: "ai", body: body, contentType: "application/json", timeout: 120.0, completion: completion)
    }

    /// Hosts the server can download a video from (TikTok, YouTube, Instagram, X, VK, Reddit, Pinterest).
    private static let videoHosts: [String] = ["tiktok.com", "youtube.com", "youtu.be", "instagram.com", "x.com", "twitter.com", "vk.com", "vkvideo.ru", "reddit.com", "pinterest.com", "pin.it", "rutube.ru", "twitch.tv"]

    public static func canDownloadVideo(url: String) -> Bool {
        guard isConfigured, let host = URL(string: url)?.host?.lowercased() else {
            return false
        }
        return videoHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
    }

    /// The server downloads the video by link (yt-dlp) and returns an mp4; completion gets a temporary file.
    public static func downloadVideo(url: String, completion: @escaping (URL?) -> Void) -> URLSessionTask? {
        guard let endpoint = baseURL?.appendingPathComponent("dl"), let body = try? JSONSerialization.data(withJSONObject: ["url": url]) else {
            completion(nil)
            return nil
        }
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 300.0)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "X-Nova-Key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = body
        let task = URLSession.shared.downloadTask(with: urlRequest, completionHandler: { location, response, _ in
            var result: URL?
            if let location = location, let response = response as? HTTPURLResponse, response.statusCode == 200, response.mimeType == "video/mp4" {
                let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("novagram-\(UUID().uuidString).mp4")
                if (try? FileManager.default.moveItem(at: location, to: target)) != nil {
                    result = target
                }
            }
            DispatchQueue.main.async {
                completion(result)
            }
        })
        task.resume()
        return task
    }

    /// The server turns a video into a round video message (to: "round", mp4 400×400) or any audio into a voice message (to: "voice", ogg/opus).
    public static func convert(path: String, to: String, completion: @escaping (URL?, Double) -> Void) -> URLSessionTask? {
        guard var components = baseURL.flatMap({ URLComponents(url: $0.appendingPathComponent("convert"), resolvingAgainstBaseURL: false) }) else {
            completion(nil, 0.0)
            return nil
        }
        components.queryItems = [URLQueryItem(name: "to", value: to)]
        guard let endpoint = components.url else {
            completion(nil, 0.0)
            return nil
        }
        var urlRequest = URLRequest(url: endpoint, timeoutInterval: 300.0)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(key, forHTTPHeaderField: "X-Nova-Key")
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let task = URLSession.shared.uploadTask(with: urlRequest, fromFile: URL(fileURLWithPath: path), completionHandler: { data, response, _ in
            var result: URL?
            var duration = 0.0
            if let data = data, let response = response as? HTTPURLResponse, response.statusCode == 200 {
                let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("novagram-\(UUID().uuidString).\(to == "round" ? "mp4" : "ogg")")
                if (try? data.write(to: target)) != nil {
                    result = target
                    duration = Double(response.value(forHTTPHeaderField: "X-Duration") ?? "") ?? 0.0
                }
            }
            DispatchQueue.main.async {
                completion(result, duration)
            }
        })
        task.resume()
        return task
    }
}
