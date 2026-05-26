import Foundation

enum IPOverviewAddressFamily: String, CaseIterable, Sendable {
    case ipv4 = "IPv4"
    case ipv6 = "IPv6"
}

struct IPOverviewPublicIPResult: Equatable, Sendable {
    let family: IPOverviewAddressFamily
    let ip: String
    let source: String
}

struct IPOverviewSourceResult: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case success(String)
        case failure(String)
    }

    let id: String
    let family: IPOverviewAddressFamily
    let source: String
    let status: Status
}

struct IPOverviewLocalAddress: Identifiable, Equatable, Sendable {
    let id: String
    let interfaceName: String
    let address: String
    let family: IPOverviewAddressFamily
}

struct IPOverviewGeoInfo: Equatable, Sendable {
    let ip: String
    let country: String?
    let countryCode: String?
    let region: String?
    let city: String?
    let isp: String?
    let organization: String?
    let asn: String?
    let timezone: String?
    let networkType: IPOverviewNetworkType
    let isProxy: Bool?
    let isHosting: Bool?
    let source: String

    var countryFlag: String? {
        guard let countryCode else {
            return nil
        }

        return IPOverviewFormatter.flagEmoji(countryCode: countryCode)
    }

    var locationText: String? {
        [country, region, city]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " / ")
            .nilIfEmpty
    }

    var countryDisplayText: String? {
        guard let country, !country.isEmpty else {
            return nil
        }

        if let countryFlag {
            return "\(countryFlag) \(country)"
        }

        return country
    }

    var networkText: String? {
        [asn, organization ?? isp]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")
            .nilIfEmpty
    }

    var proxyText: String {
        switch isProxy {
        case true:
            return "可能为代理"
        case false:
            return "未识别为代理"
        case nil:
            return "未知"
        }
    }
}

enum IPOverviewNetworkType: String, Sendable {
    case residential = "住宅/宽带"
    case mobile = "移动网络"
    case datacenter = "数据中心"
    case education = "教育网络"
    case business = "企业网络"
    case unknown = "未知"

    static func infer(organization: String?, isp: String?, isHosting: Bool?) -> IPOverviewNetworkType {
        if isHosting == true {
            return .datacenter
        }

        let text = [organization, isp]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        guard !text.isEmpty else {
            return .unknown
        }

        if text.contains("mobile") || text.contains("wireless") || text.contains("cellular")
            || text.contains("移动") || text.contains("unicom") || text.contains("telecom") {
            return .mobile
        }

        if text.contains("university") || text.contains("education") || text.contains("college") {
            return .education
        }

        if text.contains("cloud") || text.contains("hosting") || text.contains("data")
            || text.contains("amazon") || text.contains("aws") || text.contains("google")
            || text.contains("microsoft") || text.contains("azure") || text.contains("cloudflare")
            || text.contains("digitalocean") || text.contains("hetzner") || text.contains("ovh")
            || text.contains("linode") || text.contains("vultr") {
            return .datacenter
        }

        if text.contains("business") || text.contains("enterprise") || text.contains("corp") {
            return .business
        }

        return .residential
    }
}

struct IPOverviewConnectivityTarget: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var name: String
    var urlString: String
    var isCustom: Bool

    var url: URL? {
        URL(string: urlString)
    }

    static let defaults: [IPOverviewConnectivityTarget] = [
        IPOverviewConnectivityTarget(
            id: "wechat",
            name: "WeChat",
            urlString: "https://res.wx.qq.com/a/wx_fed/assets/res/NTI4MWU5.ico",
            isCustom: false
        ),
        IPOverviewConnectivityTarget(
            id: "google",
            name: "Google",
            urlString: "https://www.google.com/favicon.ico",
            isCustom: false
        ),
        IPOverviewConnectivityTarget(
            id: "cloudflare",
            name: "Cloudflare",
            urlString: "https://www.cloudflare.com/favicon.ico",
            isCustom: false
        ),
        IPOverviewConnectivityTarget(
            id: "youtube",
            name: "YouTube",
            urlString: "https://www.youtube.com/favicon.ico",
            isCustom: false
        ),
        IPOverviewConnectivityTarget(
            id: "github",
            name: "GitHub",
            urlString: "https://github.com/favicon.ico",
            isCustom: false
        ),
        IPOverviewConnectivityTarget(
            id: "chatgpt",
            name: "ChatGPT",
            urlString: "https://chatgpt.com/favicon.ico",
            isCustom: false
        )
    ]
}

struct IPOverviewConnectivityResult: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case checking
        case reachable(milliseconds: Int)
        case unreachable(String)
    }

    let id: String
    let target: IPOverviewConnectivityTarget
    var status: Status

    var latencyMilliseconds: Int? {
        guard case .reachable(let milliseconds) = status else {
            return nil
        }

        return milliseconds
    }
}

struct IPOverviewLeakTestResult: Identifiable, Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case waiting
        case checking
        case success(IPOverviewLeakEndpoint)
        case failure(String)
    }

    let id: String
    let name: String
    let status: Status
}

struct IPOverviewLeakEndpoint: Equatable, Sendable {
    let ip: String
    let natType: String?
    let country: String?
    let countryCode: String?
    let organization: String?

    var countryDisplayText: String? {
        guard let country, !country.isEmpty else {
            return nil
        }

        if let countryCode, let flag = IPOverviewFormatter.flagEmoji(countryCode: countryCode) {
            return "\(flag) \(country)"
        }

        return country
    }
}

struct IPOverviewWebRTCTarget: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let host: String
    let port: UInt16

    var displayAddress: String {
        "\(host):\(port)"
    }

    static let defaults: [IPOverviewWebRTCTarget] = [
        IPOverviewWebRTCTarget(id: "google", name: "Google", host: "stun.l.google.com", port: 19302),
        IPOverviewWebRTCTarget(id: "blackberry", name: "BlackBerry", host: "stun.voip.blackberry.com", port: 3478),
        IPOverviewWebRTCTarget(id: "twilio", name: "Twilio", host: "global.stun.twilio.com", port: 3478),
        IPOverviewWebRTCTarget(id: "cloudflare", name: "Cloudflare", host: "stun.cloudflare.com", port: 3478)
    ]
}

struct IPOverviewSnapshot: Equatable, Sendable {
    var publicIPv4: IPOverviewPublicIPResult?
    var publicIPv6: IPOverviewPublicIPResult?
    var localAddresses: [IPOverviewLocalAddress]
    var geoInfoByIP: [String: IPOverviewGeoInfo]
    var sourceResults: [IPOverviewSourceResult]
    var lastUpdated: Date?
    var errorMessage: String?
    var isRefreshing: Bool

    static let empty = IPOverviewSnapshot(
        publicIPv4: nil,
        publicIPv6: nil,
        localAddresses: [],
        geoInfoByIP: [:],
        sourceResults: [],
        lastUpdated: nil,
        errorMessage: nil,
        isRefreshing: false
    )

    var preferredPublicIP: IPOverviewPublicIPResult? {
        publicIPv4 ?? publicIPv6
    }

    var preferredGeoInfo: IPOverviewGeoInfo? {
        guard let ip = preferredPublicIP?.ip else {
            return nil
        }

        return geoInfoByIP[ip]
    }

    var reportText: String {
        var lines: [String] = []
        lines.append("IP 检测结果")
        if let lastUpdated {
            lines.append("更新时间：\(IPOverviewFormatter.dateTime(lastUpdated))")
        }
        lines.append("公网 IPv4：\(publicIPv4?.ip ?? "未检测到")")
        lines.append("公网 IPv6：\(publicIPv6?.ip ?? "未检测到")")

        if !localAddresses.isEmpty {
            lines.append("")
            lines.append("本地地址：")
            for address in localAddresses {
                lines.append("- \(address.interfaceName) \(address.family.rawValue)：\(address.address)")
            }
        }

        if !geoInfoByIP.isEmpty {
            lines.append("")
            lines.append("归属地：")
            for info in geoInfoByIP.values.sorted(by: { $0.ip < $1.ip }) {
                lines.append("- \(info.ip)")
                if let country = info.countryDisplayText {
                    lines.append("  地区：\(country)")
                }
                if let region = info.region, !region.isEmpty {
                    lines.append("  省份：\(region)")
                }
                if let city = info.city, !city.isEmpty {
                    lines.append("  城市：\(city)")
                }
                if let network = info.networkText {
                    lines.append("  网络：\(network)")
                }
                lines.append("  类型：\(info.networkType.rawValue)")
                lines.append("  代理：\(info.proxyText)")
                if let timezone = info.timezone, !timezone.isEmpty {
                    lines.append("  时区：\(timezone)")
                }
                lines.append("  来源：\(info.source)")
            }
        }

        if !sourceResults.isEmpty {
            lines.append("")
            lines.append("检测源：")
            for result in sourceResults {
                switch result.status {
                case .success(let ip):
                    lines.append("- \(result.source) \(result.family.rawValue)：\(ip)")
                case .failure(let message):
                    lines.append("- \(result.source) \(result.family.rawValue)：失败（\(message)）")
                }
            }
        }

        if let errorMessage, !errorMessage.isEmpty {
            lines.append("")
            lines.append("错误：\(errorMessage)")
        }

        return lines.joined(separator: "\n")
    }
}

enum IPOverviewFormatter {
    static func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    static func flagEmoji(countryCode: String) -> String? {
        let code = countryCode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        guard code.count == 2 else {
            return nil
        }

        var scalars = String.UnicodeScalarView()
        for scalar in code.unicodeScalars {
            guard let regionalIndicator = UnicodeScalar(127397 + scalar.value) else {
                return nil
            }
            scalars.append(regionalIndicator)
        }

        return String(scalars)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
