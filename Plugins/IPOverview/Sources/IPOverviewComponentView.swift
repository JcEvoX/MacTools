import SwiftUI

struct IPOverviewComponentView: View {
    @ObservedObject var viewModel: IPOverviewViewModel
    let startsInDetails: Bool
    let showsBackButton: Bool
    @State private var customName = ""
    @State private var customURL = ""
    @State private var addError = ""

    init(
        viewModel: IPOverviewViewModel,
        startsInDetails: Bool = false,
        showsBackButton: Bool = true
    ) {
        self.viewModel = viewModel
        self.startsInDetails = startsInDetails
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        Group {
            if viewModel.isShowingDetails {
                detailPage
            } else {
                landingCard
            }
        }
        .onAppear {
            viewModel.refreshIfNeeded()
            if startsInDetails {
                viewModel.showDetails()
            }
        }
    }

    private var landingCard: some View {
        Button {
            viewModel.showDetails()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "network")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemBlue))
                        .frame(width: 30, height: 30)
                        .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("IP 检测")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(viewModel.snapshot.preferredGeoInfo?.locationText ?? "公网、归属地与连通性")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    if viewModel.snapshot.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    landingMetric(title: "IPv4", value: viewModel.snapshot.publicIPv4?.ip ?? "检测中")
                    landingMetric(title: "IPv6", value: viewModel.snapshot.publicIPv6?.ip ?? "未检测到")
                    landingMetric(title: "本地", value: viewModel.snapshot.localAddresses.first?.address ?? "等待")
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detailPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            detailHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    ipCard(index: 1, title: "IP 来源: IPCheck.ing IPv4", result: viewModel.snapshot.publicIPv4)
                    ipCard(index: 2, title: "IP 来源: IPCheck.ing IPv6", result: viewModel.snapshot.publicIPv6)
                    localAddressSection
                    connectivitySection
                    webRTCLeakSection
                    dnsLeakSection
                    privacyFooter
                }
                .padding(.bottom, 2)
            }
        }
        .padding(10)
        .onAppear {
            viewModel.checkDiagnosticsIfNeeded()
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            if showsBackButton {
                Button {
                    viewModel.showSummary()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .help("返回概览")
            }

            Text("IP 详情")
                .font(.headline)

            Spacer(minLength: 8)

            if viewModel.snapshot.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                viewModel.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isRefreshingAll)
            .help("刷新全部检测")

            Button {
                viewModel.copy(viewModel.snapshot.reportText)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.snapshot.lastUpdated == nil)
            .help("复制完整检测结果")
        }
    }

    private func ipCard(index: Int, title: String, result: IPOverviewPublicIPResult?) -> some View {
        let geoInfo = result.flatMap { viewModel.snapshot.geoInfoByIP[$0.ip] }

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(result == nil ? Color.secondary : Color.primary, in: Circle())

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(result == nil ? .secondary : .primary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.snapshot.isRefreshing)
            }
            .padding(10)

            Divider()

            if let result {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.secondary)
                        Text(result.ip)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Button {
                            viewModel.copy(result.ip)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }

                    if let geoInfo {
                        geoGrid(geoInfo)
                        Divider()
                        networkGrid(geoInfo)
                        Divider()
                        HStack(spacing: 6) {
                            Image(systemName: "building.2")
                                .foregroundStyle(.secondary)
                            Text("ASN")
                                .foregroundStyle(.secondary)
                            Text(geoInfo.asn ?? "未知")
                                .font(.system(.body, design: .monospaced))
                            Spacer(minLength: 6)
                            Button {
                                viewModel.copy(geoInfo.asn)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.borderless)
                            .disabled(geoInfo.asn == nil)
                        }
                        .font(.caption)
                    } else {
                        Text("归属地信息获取中或不可用")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("获取失败或不存在 \(index == 2 ? "IPv6" : "IPv4") 地址")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding(12)
            }
        }
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.35), lineWidth: 1)
        )
    }

    private func geoGrid(_ geoInfo: IPOverviewGeoInfo) -> some View {
        HStack(alignment: .top, spacing: 14) {
            locationValue(geoInfo.countryDisplayText ?? "未知", icon: "mappin")
            locationValue(geoInfo.region ?? "未知", icon: "house")
            locationValue(geoInfo.city ?? "未知", icon: "arrow.turn.down.right")
        }
    }

    private func locationValue(_ value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(value)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func networkGrid(_ geoInfo: IPOverviewGeoInfo) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
            GridRow {
                infoCell(icon: "server.rack", title: "网络", value: geoInfo.organization ?? geoInfo.isp ?? "未知")
                infoCell(icon: "chart.bar", title: "类型", value: geoInfo.networkType.rawValue)
            }
            GridRow {
                infoCell(icon: "shield", title: "代理", value: geoInfo.proxyText)
                infoCell(icon: "clock", title: "时区", value: geoInfo.timezone ?? "未知")
            }
        }
    }

    private func infoCell(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var localAddressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "本地局域网 IP", icon: "wifi.router")

            if viewModel.snapshot.localAddresses.isEmpty {
                Text("未检测到可用本地地址")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.snapshot.localAddresses.prefix(5)) { address in
                    HStack(spacing: 8) {
                        Text(address.interfaceName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .leading)
                        Text(address.address)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        Text(address.family.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var connectivitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                sectionHeader(title: "网络连通性", icon: "point.3.connected.trianglepath.dotted")
                Spacer(minLength: 4)
                Button {
                    viewModel.checkConnectivity()
                } label: {
                    Image(systemName: viewModel.isCheckingConnectivity ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isCheckingConnectivity)
                .help("刷新连通性")
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(viewModel.connectivityResults) { result in
                    connectivityTile(result)
                }
            }

            customTargetForm
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var webRTCLeakSection: some View {
        leakSection(
            title: "WebRTC 泄露测试",
            icon: "network.badge.shield.half.filled",
            note: "WebRTC 往往通过 UDP 直连进行建立，如果测试返回了真实 IP，则意味着你的代理设置没有覆盖这些连接。除了检测你连接 WebRTC 时所使用的 IP，我们还会检测你的 NAT 类型。然而，NAT 类型的检测并不是 100% 准确的，仅供参考。",
            isRunning: viewModel.isCheckingWebRTC,
            action: { viewModel.checkWebRTCLeak() },
            results: viewModel.webRTCResults,
            showsNAT: true
        )
    }

    private var dnsLeakSection: some View {
        leakSection(
            title: "DNS 泄漏测试",
            icon: "octagon.fill",
            note: "DNS 泄露（DNS Leaks）的意思是，当你挂上 VPN/代理后，你解析域名时，依然通过当地的运营商进行解析，这时就有 DNS 泄露的风险。\n\n泄露测试的方法是通过访问新生成的域名，检测你是通过哪个地区的 DNS 出口进行解析，如果返回的出口区域和你当地的运营商区域相同，则有 DNS 泄露风险，你可能需要修改 VPN/代理设置。",
            isRunning: viewModel.isCheckingDNSLeak,
            action: { viewModel.checkDNSLeak() },
            results: viewModel.dnsLeakResults,
            showsNAT: false
        )
    }

    private func leakSection(
        title: String,
        icon: String,
        note: String,
        isRunning: Bool,
        action: @escaping () -> Void,
        results: [IPOverviewLeakTestResult],
        showsNAT: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Spacer(minLength: 4)
                Button(action: action) {
                    Image(systemName: isRunning ? "hourglass" : "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(isRunning)
            }

            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(results) { result in
                    leakTile(result, showsNAT: showsNAT)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func leakTile(_ result: IPOverviewLeakTestResult, showsNAT: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(.secondary)
                Text(result.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(leakColor(result.status))
                    .frame(width: 8, height: 8)
                Text(leakPrimaryText(result.status))
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            VStack(alignment: .leading, spacing: 5) {
                if showsNAT {
                    leakInfoLine(title: "NAT", value: leakEndpoint(result.status)?.natType ?? "未知")
                }
                leakInfoLine(title: "网络", value: leakEndpoint(result.status)?.organization ?? "未知")
                leakInfoLine(title: "出口地区", value: leakEndpoint(result.status)?.countryDisplayText ?? "未知")
            }
            .padding(8)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private func leakInfoLine(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func connectivityTile(_ result: IPOverviewConnectivityResult) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(connectivityColor(result.status))
                    .frame(width: 8, height: 8)
                Text(result.target.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if result.target.isCustom {
                    Button {
                        viewModel.removeConnectivityTarget(id: result.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }
            }

            Text(connectivityText(result.status))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
    }

    private var customTargetForm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("名称", text: $customName)
                    .textFieldStyle(.roundedBorder)
                TextField("https://example.com", text: $customURL)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addCustomTarget()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(customName.isEmpty || customURL.isEmpty)
            }

            if !addError.isEmpty {
                Text(addError)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
    }

    private var privacyFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text("公网、归属地和连通性检测会请求外部服务；本地地址仅在本机读取。")
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func landingMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionHeader(title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func addCustomTarget() {
        if let error = viewModel.addConnectivityTarget(name: customName, urlString: customURL) {
            addError = error
            return
        }

        addError = ""
        customName = ""
        customURL = ""
    }

    private func connectivityColor(_ status: IPOverviewConnectivityResult.Status) -> Color {
        switch status {
        case .waiting:
            return .secondary.opacity(0.45)
        case .checking:
            return Color(nsColor: .systemBlue)
        case .reachable(let milliseconds):
            return milliseconds < 250 ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
        case .unreachable:
            return Color(nsColor: .systemRed)
        }
    }

    private func connectivityText(_ status: IPOverviewConnectivityResult.Status) -> String {
        switch status {
        case .waiting:
            return "等待检测"
        case .checking:
            return "检测中"
        case .reachable(let milliseconds):
            return "\(milliseconds) ms"
        case .unreachable:
            return "不可达"
        }
    }

    private func leakEndpoint(_ status: IPOverviewLeakTestResult.Status) -> IPOverviewLeakEndpoint? {
        guard case .success(let endpoint) = status else {
            return nil
        }

        return endpoint
    }

    private func leakColor(_ status: IPOverviewLeakTestResult.Status) -> Color {
        switch status {
        case .waiting:
            return .secondary.opacity(0.45)
        case .checking:
            return Color(nsColor: .systemBlue)
        case .success:
            return Color(nsColor: .systemGreen)
        case .failure:
            return Color(nsColor: .systemRed)
        }
    }

    private func leakPrimaryText(_ status: IPOverviewLeakTestResult.Status) -> String {
        switch status {
        case .waiting:
            return "等待检测"
        case .checking:
            return "检测中"
        case .success(let endpoint):
            return endpoint.ip
        case .failure:
            return "获取失败"
        }
    }
}
