import Foundation

protocol IPOverviewConnectivityChecking: Sendable {
    func check(target: IPOverviewConnectivityTarget) async -> IPOverviewConnectivityResult
}

struct IPOverviewConnectivityService: IPOverviewConnectivityChecking {
    private let httpClient: any IPOverviewHTTPClient
    private let timeout: TimeInterval

    init(
        httpClient: any IPOverviewHTTPClient = URLSession.shared,
        timeout: TimeInterval = 3
    ) {
        self.httpClient = httpClient
        self.timeout = timeout
    }

    func check(target: IPOverviewConnectivityTarget) async -> IPOverviewConnectivityResult {
        guard let url = target.url else {
            return IPOverviewConnectivityResult(
                id: target.id,
                target: target,
                status: .unreachable("URL 无效")
            )
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpMethod = "GET"
        request.setValue("MacTools IP Overview", forHTTPHeaderField: "User-Agent")

        let startedAt = Date()
        do {
            let (_, response) = try await httpClient.data(for: request)
            let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) * 1000))
            if (200..<500).contains(response.statusCode) {
                return IPOverviewConnectivityResult(
                    id: target.id,
                    target: target,
                    status: .reachable(milliseconds: elapsed)
                )
            }

            return IPOverviewConnectivityResult(
                id: target.id,
                target: target,
                status: .unreachable("HTTP \(response.statusCode)")
            )
        } catch {
            return IPOverviewConnectivityResult(
                id: target.id,
                target: target,
                status: .unreachable(error.localizedDescription)
            )
        }
    }
}
