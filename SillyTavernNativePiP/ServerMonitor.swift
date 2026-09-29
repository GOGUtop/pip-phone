import Foundation
import WebKit

/// Polls the SillyTavern server-side generation monitor from the native process.
///
/// This is intentionally independent from WKWebView JavaScript. iOS may suspend the
/// WebContent process while native PiP keeps the app alive; URLSession polling from
/// the app process can still observe the server-side job state and schedule a local
/// notification as soon as the upstream generation is finished.
final class ServerMonitor {
    typealias CookieProvider = (@escaping (String?) -> Void) -> Void

    struct Job: Decodable {
        let id: String
        let state: String
        let target: String?
        let startedAt: String?
        let updatedAt: String?
        let finishedAt: String?
        let activeRequests: Int?
        let requestCount: Int?
        let statusCode: Int?
        let error: String?
    }

    struct StatusEnvelope: Decodable {
        let ok: Bool
        let version: String?
        let job: Job?
    }

    var cookieProvider: CookieProvider?
    var onStateChanged: ((String, String?) -> Void)?

    private let statusURL: URL
    private let deviceID: String
    private let session: URLSession
    private let queue = DispatchQueue(label: "st.native.server-monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var requestInFlight = false
    private var baselineEstablished = false
    private var trackedGeneratingJobID: String?
    private var lastNotifiedJobID: String?
    private var lastReportedState = "starting"

    init(statusURL: URL, deviceID: String) {
        self.statusURL = statusURL
        self.deviceID = deviceID
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + 0.4, repeating: 1.5, leeway: .milliseconds(250))
            timer.setEventHandler { [weak self] in self?.poll() }
            self.timer = timer
            timer.resume()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    func pollNow() {
        queue.async { [weak self] in self?.poll() }
    }

    private func poll() {
        guard !requestInFlight else { return }
        requestInFlight = true

        cookieProvider? { [weak self] cookieHeader in
            guard let self else { return }
            self.queue.async {
                var components = URLComponents(url: self.statusURL, resolvingAgainstBaseURL: false)
                var items = components?.queryItems ?? []
                items.removeAll { $0.name == "deviceId" }
                items.append(URLQueryItem(name: "deviceId", value: self.deviceID))
                components?.queryItems = items
                guard let url = components?.url else {
                    self.finishRequest(state: "bad-status-url", detail: nil)
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
                request.setValue(self.deviceID, forHTTPHeaderField: "X-ST-Native-Device-ID")
                if let cookieHeader, !cookieHeader.isEmpty {
                    request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
                }

                let task = self.session.dataTask(with: request) { [weak self] data, response, error in
                    guard let self else { return }
                    self.queue.async {
                        defer { self.requestInFlight = false }

                        if let error {
                            self.reportState("offline", detail: error.localizedDescription)
                            return
                        }
                        guard let http = response as? HTTPURLResponse else {
                            self.reportState("bad-response", detail: nil)
                            return
                        }
                        guard (200..<300).contains(http.statusCode), let data else {
                            self.reportState("http-\(http.statusCode)", detail: nil)
                            return
                        }

                        do {
                            let envelope = try JSONDecoder().decode(StatusEnvelope.self, from: data)
                            self.consume(envelope)
                        } catch {
                            self.reportState("decode-error", detail: error.localizedDescription)
                        }
                    }
                }
                task.resume()
            }
        }

        if cookieProvider == nil {
            var components = URLComponents(url: statusURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "deviceId", value: deviceID)]
            guard let url = components?.url else {
                finishRequest(state: "bad-status-url", detail: nil)
                return
            }
            var request = URLRequest(url: url)
            request.setValue(deviceID, forHTTPHeaderField: "X-ST-Native-Device-ID")
            let task = session.dataTask(with: request) { [weak self] data, response, error in
                guard let self else { return }
                self.queue.async {
                    defer { self.requestInFlight = false }
                    if let error {
                        self.reportState("offline", detail: error.localizedDescription)
                        return
                    }
                    guard let http = response as? HTTPURLResponse,
                          (200..<300).contains(http.statusCode),
                          let data,
                          let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data) else {
                        self.reportState("unavailable", detail: nil)
                        return
                    }
                    self.consume(envelope)
                }
            }
            task.resume()
        }
    }

    private func finishRequest(state: String, detail: String?) {
        requestInFlight = false
        reportState(state, detail: detail)
    }

    private func consume(_ envelope: StatusEnvelope) {
        guard envelope.ok else {
            reportState("server-error", detail: nil)
            return
        }

        guard let job = envelope.job else {
            baselineEstablished = true
            trackedGeneratingJobID = nil
            reportState("idle", detail: envelope.version)
            return
        }

        if !baselineEstablished {
            baselineEstablished = true
            if job.state == "generating" || job.state == "settling" {
                trackedGeneratingJobID = job.id
            } else {
                lastNotifiedJobID = job.id
            }
        }

        switch job.state {
        case "generating", "settling":
            trackedGeneratingJobID = job.id
            reportState(job.state, detail: envelope.version)

        case "done":
            let isNewCompletion = job.id != lastNotifiedJobID &&
                (trackedGeneratingJobID == job.id || baselineEstablished)
            if isNewCompletion {
                lastNotifiedJobID = job.id
                trackedGeneratingJobID = nil
                NotificationManager.shared.notify(
                    title: "SillyTavern 回复完成",
                    body: "当前回复已经生成完毕。",
                    completion: nil
                )
            }
            reportState("done", detail: envelope.version)

        case "cancelled":
            if trackedGeneratingJobID == job.id { trackedGeneratingJobID = nil }
            lastNotifiedJobID = job.id
            reportState("cancelled", detail: envelope.version)

        case "error":
            if trackedGeneratingJobID == job.id { trackedGeneratingJobID = nil }
            lastNotifiedJobID = job.id
            reportState("error", detail: job.error ?? envelope.version)

        default:
            reportState(job.state, detail: envelope.version)
        }
    }

    private func reportState(_ state: String, detail: String?) {
        guard state != lastReportedState || detail != nil else { return }
        lastReportedState = state
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(state, detail)
        }
    }
}
