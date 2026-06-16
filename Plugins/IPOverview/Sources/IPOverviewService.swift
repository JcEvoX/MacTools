import Darwin
import Foundation
import MacToolsPluginKit

protocol IPOverviewProviding: Sendable {
    func collectSnapshot() async -> IPOverviewSnapshot
}

protocol IPOverviewHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: IPOverviewHTTPClient {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request, delegate: nil)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw IPOverviewServiceError.invalidResponse
        }

        return (data, httpResponse)
    }
}

enum IPOverviewServiceError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case invalidPayload
    case invalidIP(String)

    var errorDescription: String? {
        localizedDescription()
    }

    func localizedDescription(localization: PluginLocalization = PluginLocalization(bundle: .main)) -> String {
        switch self {
        case .invalidResponse:
            return localization.string("service.error.invalidResponse", defaultValue: "响应无效")
        case .badStatus(let statusCode):
            return "HTTP \(statusCode)"
        case .invalidPayload:
            return localization.string("service.error.invalidPayload", defaultValue: "数据格式不正确")
        case .invalidIP(let value):
            return localization.format("service.error.invalidIP", defaultValue: "IP 无效：%@", value)
        }
    }
}

struct IPOverviewService: IPOverviewProviding {
    private let httpClient: any IPOverviewHTTPClient
    private let timeout: TimeInterval
    private let localization: PluginLocalization

    init(
        httpClient: any IPOverviewHTTPClient = URLSession.shared,
        timeout: TimeInterval = 4,
        localization: PluginLocalization = PluginLocalization(bundle: .main)
    ) {
        self.httpClient = httpClient
        self.timeout = timeout
        self.localization = localization
    }

    func collectSnapshot() async -> IPOverviewSnapshot {
        async let localAddresses = Self.localAddresses()
        async let ipv4Results = fetchPublicIP(family: .ipv4)
        async let ipv6Results = fetchPublicIP(family: .ipv6)

        let local = await localAddresses
        let ipv4 = await ipv4Results
        let ipv6 = await ipv6Results
        let sourceResults = ipv4.results + ipv6.results
        let publicIPv4 = ipv4.best
        let publicIPv6 = ipv6.best

        var geoInfoByIP: [String: IPOverviewGeoInfo] = [:]
        for result in [publicIPv4, publicIPv6].compactMap({ $0 }) {
            if let geoInfo = await fetchGeoInfo(ip: result.ip) {
                geoInfoByIP[result.ip] = geoInfo
            }
        }

        let errorMessage: String?
        if publicIPv4 == nil && publicIPv6 == nil {
            errorMessage = localization.string(
                "service.error.noPublicIP",
                defaultValue: "未能从外部检测源获取公网 IP"
            )
        } else {
            errorMessage = nil
        }

        return IPOverviewSnapshot(
            publicIPv4: publicIPv4,
            publicIPv6: publicIPv6,
            localAddresses: local,
            geoInfoByIP: geoInfoByIP,
            sourceResults: sourceResults,
            lastUpdated: Date(),
            errorMessage: errorMessage,
            isRefreshing: false
        )
    }

    private func fetchPublicIP(
        family: IPOverviewAddressFamily
    ) async -> (best: IPOverviewPublicIPResult?, results: [IPOverviewSourceResult]) {
        var best: IPOverviewPublicIPResult?
        var results: [IPOverviewSourceResult] = []

        for source in IPOverviewPublicIPSource.sources(for: family) {
            do {
                let ip = try await fetchIP(from: source)
                let result = IPOverviewPublicIPResult(
                    family: family,
                    ip: ip,
                    source: source.name
                )
                if best == nil {
                    best = result
                }
                results.append(IPOverviewSourceResult(
                    id: source.id,
                    family: family,
                    source: source.name,
                    status: .success(ip)
                ))
            } catch {
                let message = (error as? IPOverviewServiceError)?
                    .localizedDescription(localization: localization)
                    ?? error.localizedDescription
                results.append(IPOverviewSourceResult(
                    id: source.id,
                    family: family,
                    source: source.name,
                    status: .failure(message)
                ))
            }
        }

        return (best, results)
    }

    private func fetchIP(from source: IPOverviewPublicIPSource) async throws -> String {
        let (data, response) = try await fetch(source.url)
        guard (200..<300).contains(response.statusCode) else {
            throw IPOverviewServiceError.badStatus(response.statusCode)
        }

        let ip: String?
        switch source.parser {
        case .jsonIP:
            ip = IPOverviewParser.ipFromJSON(data)
        case .cloudflareTrace:
            ip = IPOverviewParser.ipFromCloudflareTrace(data)
        case .plainText:
            ip = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let ip else {
            throw IPOverviewServiceError.invalidPayload
        }

        guard Self.isValidIPAddress(ip, family: source.family) else {
            throw IPOverviewServiceError.invalidIP(ip)
        }

        return ip
    }

    private func fetchGeoInfo(ip: String) async -> IPOverviewGeoInfo? {
        for source in IPOverviewGeoSource.allCases {
            do {
                let (data, response) = try await fetch(source.url(ip: ip))
                guard (200..<300).contains(response.statusCode) else {
                    continue
                }

                switch source {
                case .ipwhois:
                    if let info = IPOverviewParser.geoInfoFromIPWhois(data, ip: ip) {
                        return info
                    }
                case .ipapi:
                    if let info = IPOverviewParser.geoInfoFromIPAPI(data, ip: ip) {
                        return info
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func fetch(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("MacTools IP Overview", forHTTPHeaderField: "User-Agent")
        return try await httpClient.data(for: request)
    }

    static func localAddresses() -> [IPOverviewLocalAddress] {
        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let firstAddress = interfaceAddresses else {
            return []
        }
        defer { freeifaddrs(interfaceAddresses) }

        var addresses: [IPOverviewLocalAddress] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let currentPointer = pointer {
            defer { pointer = currentPointer.pointee.ifa_next }

            let name = String(cString: currentPointer.pointee.ifa_name)
            guard !isNoiseInterface(name),
                  (currentPointer.pointee.ifa_flags & UInt32(IFF_UP)) != 0,
                  let socketAddress = currentPointer.pointee.ifa_addr
            else {
                continue
            }

            let family: IPOverviewAddressFamily
            switch Int32(socketAddress.pointee.sa_family) {
            case AF_INET:
                family = .ipv4
            case AF_INET6:
                family = .ipv6
            default:
                continue
            }

            guard let address = numericAddress(from: socketAddress),
                  isUsableLocalAddress(address, family: family)
            else {
                continue
            }

            addresses.append(IPOverviewLocalAddress(
                id: "\(name)-\(address)",
                interfaceName: name,
                address: address,
                family: family
            ))
        }

        return addresses.sorted {
            if $0.interfaceName == $1.interfaceName {
                return $0.address < $1.address
            }

            return $0.interfaceName < $1.interfaceName
        }
    }

    static func isValidIPAddress(_ value: String, family: IPOverviewAddressFamily? = nil) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()

        switch family {
        case .ipv4:
            return inet_pton(AF_INET, value, &ipv4) == 1
        case .ipv6:
            return inet_pton(AF_INET6, value, &ipv6) == 1
        case nil:
            return inet_pton(AF_INET, value, &ipv4) == 1
                || inet_pton(AF_INET6, value, &ipv6) == 1
        }
    }

    private static func numericAddress(from pointer: UnsafePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            pointer,
            socklen_t(pointer.pointee.sa_len),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        )

        guard result == 0 else {
            return nil
        }

        let nullIndex = host.firstIndex(of: 0) ?? host.endIndex
        let bytes = host[..<nullIndex].map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).nilIfEmpty
    }

    private static func isUsableLocalAddress(
        _ address: String,
        family: IPOverviewAddressFamily
    ) -> Bool {
        switch family {
        case .ipv4:
            return !address.hasPrefix("127.") && address != "0.0.0.0"
        case .ipv6:
            return !address.hasPrefix("::1")
                && !address.lowercased().hasPrefix("fe80")
        }
    }

    private static func isNoiseInterface(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        let noisePrefixes = ["lo", "awdl", "utun", "llw", "bridge", "gif", "stf", "xhc", "anpi"]
        return noisePrefixes.contains { lowercasedName.hasPrefix($0) }
    }
}

struct IPOverviewPublicIPSource: Sendable {
    enum Parser: Sendable {
        case jsonIP
        case cloudflareTrace
        case plainText
    }

    let id: String
    let name: String
    let family: IPOverviewAddressFamily
    let url: URL
    let parser: Parser

    static func sources(for family: IPOverviewAddressFamily) -> [IPOverviewPublicIPSource] {
        switch family {
        case .ipv4:
            return [
                IPOverviewPublicIPSource(
                    id: "ipcheck-v4-json",
                    name: "IPCheck.ing IPv4",
                    family: .ipv4,
                    url: URL(string: "https://4.ipcheck.ing")!,
                    parser: .jsonIP
                ),
                IPOverviewPublicIPSource(
                    id: "ipcheck-v4-trace",
                    name: "IPCheck.ing Trace IPv4",
                    family: .ipv4,
                    url: URL(string: "https://4.ipcheck.ing/cdn-cgi/trace")!,
                    parser: .cloudflareTrace
                ),
                IPOverviewPublicIPSource(
                    id: "ipify-v4",
                    name: "IPify IPv4",
                    family: .ipv4,
                    url: URL(string: "https://api4.ipify.org?format=json")!,
                    parser: .jsonIP
                ),
                IPOverviewPublicIPSource(
                    id: "ifconfig-v4",
                    name: "ifconfig.me IPv4",
                    family: .ipv4,
                    url: URL(string: "https://ifconfig.me/ip")!,
                    parser: .plainText
                )
            ]
        case .ipv6:
            return [
                IPOverviewPublicIPSource(
                    id: "ipcheck-v6-json",
                    name: "IPCheck.ing IPv6",
                    family: .ipv6,
                    url: URL(string: "https://6.ipcheck.ing")!,
                    parser: .jsonIP
                ),
                IPOverviewPublicIPSource(
                    id: "ipcheck-v6-trace",
                    name: "IPCheck.ing Trace IPv6",
                    family: .ipv6,
                    url: URL(string: "https://6.ipcheck.ing/cdn-cgi/trace")!,
                    parser: .cloudflareTrace
                ),
                IPOverviewPublicIPSource(
                    id: "ipify-v6",
                    name: "IPify IPv6",
                    family: .ipv6,
                    url: URL(string: "https://api6.ipify.org?format=json")!,
                    parser: .jsonIP
                )
            ]
        }
    }
}

enum IPOverviewGeoSource: CaseIterable {
    case ipwhois
    case ipapi

    func url(ip: String) -> URL {
        switch self {
        case .ipwhois:
            return URL(string: "https://ipwho.is/\(ip)")!
        case .ipapi:
            return URL(string: "https://ipapi.co/\(ip)/json/")!
        }
    }
}

enum IPOverviewParser {
    static func ipFromJSON(_ data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let ip = object["ip"] as? String
        else {
            return nil
        }

        return ip.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    static func ipFromCloudflareTrace(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return text
            .split(separator: "\n")
            .first { $0.hasPrefix("ip=") }
            .map { String($0.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines) }?
            .nilIfEmpty
    }

    static func geoInfoFromIPWhois(_ data: Data, ip: String) -> IPOverviewGeoInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let success = object["success"] as? Bool, success == false {
            return nil
        }

        let connection = object["connection"] as? [String: Any]
        let timezone = object["timezone"] as? [String: Any]
        let asnValue = connection?["asn"].map { value in
            if let intValue = value as? Int {
                return "AS\(intValue)"
            }
            return "\(value)"
        }

        return IPOverviewGeoInfo(
            ip: ip,
            country: object["country"] as? String,
            countryCode: object["country_code"] as? String,
            region: object["region"] as? String,
            city: object["city"] as? String,
            isp: connection?["isp"] as? String,
            organization: connection?["org"] as? String,
            asn: asnValue,
            timezone: timezone?["id"] as? String,
            networkType: IPOverviewNetworkType.infer(
                organization: connection?["org"] as? String,
                isp: connection?["isp"] as? String,
                isHosting: nil
            ),
            isProxy: nil,
            isHosting: nil,
            source: "ipwho.is"
        )
    }

    static func geoInfoFromIPAPI(_ data: Data, ip: String) -> IPOverviewGeoInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if object["error"] as? Bool == true {
            return nil
        }

        let asn = object["asn"] as? String
        let organization = object["org"] as? String
        return IPOverviewGeoInfo(
            ip: ip,
            country: object["country_name"] as? String,
            countryCode: object["country_code"] as? String,
            region: object["region"] as? String,
            city: object["city"] as? String,
            isp: organization,
            organization: organization,
            asn: asn?.hasPrefix("AS") == true ? asn : asn.map { "AS\($0)" },
            timezone: object["timezone"] as? String,
            networkType: IPOverviewNetworkType.infer(
                organization: organization,
                isp: organization,
                isHosting: nil
            ),
            isProxy: nil,
            isHosting: nil,
            source: "ipapi.co"
        )
    }
}
