import AppKit
import AVFoundation
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum MenuBarIconAppearance: String, CaseIterable, Identifiable, Codable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return "浅色模式"
        case .dark:
            return "深色模式"
        }
    }
}

enum MenuBarIconRenderMode: String, CaseIterable, Identifiable, Codable {
    case original
    case template

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original:
            return "保留原图"
        case .template:
            return "模板图标"
        }
    }
}

struct MenuBarIconAdjustment: Codable, Equatable {
    var scale: Double
    var offsetX: Double
    var offsetY: Double

    static let `default` = MenuBarIconAdjustment(scale: 1, offsetX: 0, offsetY: 0)
}

enum MenuBarIconAnimationSpeedMode: String, CaseIterable, Identifiable, Codable {
    case manual
    case adaptiveSystemLoad

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return "手动速度"
        case .adaptiveSystemLoad:
            return "随系统负载"
        }
    }
}

struct MenuBarIconAnimationSystemLoad: Equatable {
    var cpuUsage: Double?
    var gpuUsage: Double?
    var memoryUsage: Double?
}

enum MenuBarIconAnimationSpeedPolicy {
    static let minimumMultiplier = 0.5
    static let maximumMultiplier = 5.0
    static let defaultManualMultiplier = 1.0

    static func normalizedManualMultiplier(_ value: Double) -> Double {
        min(max(value, minimumMultiplier), maximumMultiplier)
    }

    static func multiplier(
        mode: MenuBarIconAnimationSpeedMode,
        manualMultiplier: Double,
        systemLoad: MenuBarIconAnimationSystemLoad?
    ) -> Double {
        switch mode {
        case .manual:
            return normalizedManualMultiplier(manualMultiplier)
        case .adaptiveSystemLoad:
            let loadValues = [
                systemLoad?.cpuUsage,
                systemLoad?.gpuUsage,
                systemLoad?.memoryUsage
            ].compactMap { $0 }.map { min(max($0, 0), 1) }

            guard !loadValues.isEmpty else {
                return defaultManualMultiplier
            }

            let averageLoad = loadValues.reduce(0, +) / Double(loadValues.count)
            return min(max(0.75 + (averageLoad * 1.25), minimumMultiplier), maximumMultiplier)
        }
    }
}

enum MenuBarIconMediaKind: String, Codable, Equatable {
    case image
    case animation
}

enum MenuBarIconBuiltInAnimationGroup: String, CaseIterable, Identifiable {
    case featured
    case animals
    case motion
    case objects
    case scenes
    case symbols

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured:
            return "精选"
        case .animals:
            return "动物"
        case .motion:
            return "运动"
        case .objects:
            return "物件"
        case .scenes:
            return "场景"
        case .symbols:
            return "图形"
        }
    }
}

struct MenuBarIconRecentItem: Identifiable, Codable, Equatable {
    let id: UUID
    var fileName: String
    var frameFileNames: [String]
    var displayName: String
    var addedAt: Date
    var mediaKind: MenuBarIconMediaKind
    var frameDuration: TimeInterval

    init(
        id: UUID,
        fileName: String,
        frameFileNames: [String],
        displayName: String,
        addedAt: Date,
        mediaKind: MenuBarIconMediaKind,
        frameDuration: TimeInterval
    ) {
        self.id = id
        self.fileName = fileName
        self.frameFileNames = frameFileNames
        self.displayName = displayName
        self.addedAt = addedAt
        self.mediaKind = mediaKind
        self.frameDuration = frameDuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fileName = try container.decode(String.self, forKey: .fileName)
        frameFileNames = try container.decodeIfPresent([String].self, forKey: .frameFileNames) ?? [fileName]
        displayName = try container.decode(String.self, forKey: .displayName)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        mediaKind = try container.decodeIfPresent(MenuBarIconMediaKind.self, forKey: .mediaKind) ?? .image
        frameDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .frameDuration) ?? 1.0 / 6.0
    }
}

struct MenuBarIconBuiltInAnimation: Identifiable, Equatable {
    let id: String
    let displayName: String
    let group: MenuBarIconBuiltInAnimationGroup
    let frameResourceNames: [String]
    let frameResourceExtension: String
    let resourceSubdirectory: String
    let frameDuration: TimeInterval

    private static func numberedFrameResourceNames(prefix: String, count: Int) -> [String] {
        (1...count).map { index in
            String(format: "%@%03d", prefix, index)
        }
    }

    private static func zeroBasedFrameResourceNames(prefix: String, count: Int) -> [String] {
        (0..<count).map { index in
            String(format: "%@-frame-%03d", prefix, index)
        }
    }

    private static func runCatAssetAnimations() -> [MenuBarIconBuiltInAnimation] {
        let assets: [(id: String, displayName: String, group: MenuBarIconBuiltInAnimationGroup, frameCount: Int)] = [
            (id: "all-runners", displayName: "全员奔跑", group: .motion, frameCount: 5),
            (id: "bird", displayName: "小鸟", group: .animals, frameCount: 5),
            (id: "bonfire", displayName: "篝火", group: .scenes, frameCount: 5),
            (id: "butterfly", displayName: "蝴蝶", group: .animals, frameCount: 5),
            (id: "cat-b", displayName: "RunCat 猫 B", group: .animals, frameCount: 5),
            (id: "cat-c", displayName: "RunCat 猫 C", group: .animals, frameCount: 5),
            (id: "cat-tail", displayName: "猫尾巴", group: .animals, frameCount: 5),
            (id: "chameleon", displayName: "变色龙", group: .animals, frameCount: 5),
            (id: "cheetah", displayName: "猎豹", group: .animals, frameCount: 5),
            (id: "chicken", displayName: "小鸡", group: .animals, frameCount: 5),
            (id: "city", displayName: "城市", group: .scenes, frameCount: 10),
            (id: "coffee", displayName: "咖啡", group: .objects, frameCount: 10),
            (id: "cogwheel", displayName: "齿轮", group: .objects, frameCount: 5),
            (id: "cradle", displayName: "摇篮", group: .objects, frameCount: 5),
            (id: "dinosaur", displayName: "恐龙", group: .animals, frameCount: 7),
            (id: "dog", displayName: "小狗", group: .animals, frameCount: 5),
            (id: "dogeza", displayName: "伏地", group: .motion, frameCount: 8),
            (id: "dolphin", displayName: "海豚", group: .animals, frameCount: 5),
            (id: "dots", displayName: "圆点", group: .symbols, frameCount: 10),
            (id: "dragon", displayName: "龙", group: .animals, frameCount: 5),
            (id: "drop", displayName: "水滴", group: .symbols, frameCount: 5),
            (id: "earth", displayName: "地球", group: .scenes, frameCount: 15),
            (id: "engine", displayName: "发动机", group: .objects, frameCount: 10),
            (id: "entaku", displayName: "圆桌", group: .objects, frameCount: 9),
            (id: "factory", displayName: "工厂", group: .scenes, frameCount: 16),
            (id: "fishman", displayName: "鱼人", group: .animals, frameCount: 5),
            (id: "flash-cat", displayName: "闪电猫", group: .featured, frameCount: 5),
            (id: "fox", displayName: "狐狸", group: .animals, frameCount: 5),
            (id: "frog", displayName: "青蛙", group: .animals, frameCount: 5),
            (id: "frypan", displayName: "煎锅", group: .objects, frameCount: 5),
            (id: "ghost", displayName: "幽灵", group: .symbols, frameCount: 5),
            (id: "golden-cat", displayName: "金猫", group: .featured, frameCount: 10),
            (id: "greyhound", displayName: "灵缇", group: .animals, frameCount: 14),
            (id: "hamster-wheel", displayName: "转轮", group: .motion, frameCount: 5),
            (id: "hedgehog", displayName: "刺猬", group: .animals, frameCount: 5),
            (id: "horse", displayName: "马", group: .animals, frameCount: 5),
            (id: "human", displayName: "跑步人", group: .motion, frameCount: 5),
            (id: "jack-o-lantern", displayName: "南瓜灯", group: .objects, frameCount: 5),
            (id: "maneki-neko", displayName: "招财猫", group: .featured, frameCount: 15),
            (id: "metal-cluster-cat", displayName: "金属猫", group: .featured, frameCount: 10),
            (id: "mochi", displayName: "麻薯", group: .objects, frameCount: 5),
            (id: "mock-nyan-cat", displayName: "彩虹猫", group: .featured, frameCount: 5),
            (id: "mouse", displayName: "小鼠", group: .animals, frameCount: 5),
            (id: "octopus", displayName: "章鱼", group: .animals, frameCount: 5),
            (id: "otter", displayName: "水獭", group: .animals, frameCount: 8),
            (id: "owl", displayName: "猫头鹰", group: .animals, frameCount: 5),
            (id: "parrot", displayName: "鹦鹉", group: .animals, frameCount: 10),
            (id: "party-people", displayName: "派对人群", group: .motion, frameCount: 14),
            (id: "pendulum", displayName: "钟摆", group: .objects, frameCount: 5),
            (id: "penguin", displayName: "企鹅", group: .animals, frameCount: 5),
            (id: "penguin2", displayName: "企鹅 2", group: .animals, frameCount: 5),
            (id: "pig", displayName: "小猪", group: .animals, frameCount: 5),
            (id: "pulse", displayName: "脉冲", group: .symbols, frameCount: 5),
            (id: "puppy", displayName: "幼犬", group: .animals, frameCount: 5),
            (id: "push-up", displayName: "俯卧撑", group: .motion, frameCount: 5),
            (id: "rabbit", displayName: "兔子", group: .animals, frameCount: 5),
            (id: "reactor", displayName: "反应堆", group: .objects, frameCount: 5),
            (id: "reindeer-sleigh", displayName: "雪橇", group: .scenes, frameCount: 5),
            (id: "rocket", displayName: "火箭", group: .objects, frameCount: 5),
            (id: "rotating-sushi", displayName: "旋转寿司", group: .objects, frameCount: 6),
            (id: "rubber-duck", displayName: "小黄鸭", group: .objects, frameCount: 5),
            (id: "sausage", displayName: "香肠", group: .objects, frameCount: 5),
            (id: "self-made", displayName: "自制", group: .symbols, frameCount: 5),
            (id: "sheep", displayName: "绵羊", group: .animals, frameCount: 5),
            (id: "sine-curve", displayName: "正弦曲线", group: .symbols, frameCount: 5),
            (id: "sit-up", displayName: "仰卧起坐", group: .motion, frameCount: 5),
            (id: "slime", displayName: "史莱姆", group: .symbols, frameCount: 5),
            (id: "snowman", displayName: "雪人", group: .scenes, frameCount: 5),
            (id: "sparkler", displayName: "烟花棒", group: .objects, frameCount: 5),
            (id: "squirrel", displayName: "松鼠", group: .animals, frameCount: 5),
            (id: "steam-locomotive", displayName: "蒸汽火车", group: .objects, frameCount: 10),
            (id: "sushi", displayName: "寿司", group: .objects, frameCount: 16),
            (id: "tapioca-drink", displayName: "珍珠奶茶", group: .objects, frameCount: 5),
            (id: "terrier", displayName: "梗犬", group: .animals, frameCount: 5),
            (id: "triforce", displayName: "三角徽记", group: .symbols, frameCount: 9),
            (id: "uhooi", displayName: "Uhooi", group: .symbols, frameCount: 10),
            (id: "welsh-corgi", displayName: "柯基", group: .animals, frameCount: 7),
            (id: "whale", displayName: "鲸鱼", group: .animals, frameCount: 5),
            (id: "wind-chime", displayName: "风铃", group: .objects, frameCount: 5)
        ]

        return assets.map { asset in
            MenuBarIconBuiltInAnimation(
                id: "runcat-\(asset.id)",
                displayName: asset.displayName,
                group: asset.group,
                frameResourceNames: Self.zeroBasedFrameResourceNames(prefix: asset.id, count: asset.frameCount),
                frameResourceExtension: "png",
                resourceSubdirectory: "BuiltinMenuBarAnimations/RunCatAssets/\(asset.id)",
                frameDuration: 0.1
            )
        }
    }

    static let all: [MenuBarIconBuiltInAnimation] = [
        MenuBarIconBuiltInAnimation(
            id: "running-left",
            displayName: "奔跑狗狗",
            group: .featured,
            frameResourceNames: Self.numberedFrameResourceNames(prefix: "runningLeft", count: 52),
            frameResourceExtension: "png",
            resourceSubdirectory: "BuiltinMenuBarAnimations/RunningLeft",
            frameDuration: 1.0 / 24.0
        ),
        MenuBarIconBuiltInAnimation(
            id: "runcat",
            displayName: "RunCat",
            group: .featured,
            frameResourceNames: ["cat0", "cat1", "cat2", "cat3", "cat4"],
            frameResourceExtension: "png",
            resourceSubdirectory: "BuiltinMenuBarAnimations/RunCat",
            frameDuration: 0.1
        )
    ] + Self.runCatAssetAnimations()

    func loadFrames(bundle: Bundle = .main) -> [NSImage] {
        frameResourceNames.compactMap { resourceName in
            loadFrame(resourceName: resourceName, bundle: bundle)
        }
    }

    func loadFirstFrame(bundle: Bundle = .main) -> NSImage? {
        guard let resourceName = frameResourceNames.first else {
            return nil
        }

        return loadFrame(resourceName: resourceName, bundle: bundle)
    }

    private func loadFrame(resourceName: String, bundle: Bundle) -> NSImage? {
        let url = bundle.url(
            forResource: resourceName,
            withExtension: frameResourceExtension,
            subdirectory: resourceSubdirectory
        ) ?? bundle.url(
            forResource: resourceName,
            withExtension: frameResourceExtension
        )

        guard let url else {
            return nil
        }

        return NSImage(contentsOf: url)
    }
}

struct MenuBarIconImagePayload: Equatable {
    let image: NSImage
    let isTemplate: Bool
    let animationFrames: [NSImage]
    let frameDuration: TimeInterval
    let speedMode: MenuBarIconAnimationSpeedMode
    let manualSpeedMultiplier: Double

    var isAnimated: Bool {
        animationFrames.count > 1
    }
}

struct MenuBarIconBackgroundRemovalOptions: Codable, Equatable {
    var isEnabled: Bool
    var tolerance: Double

    static let `default` = MenuBarIconBackgroundRemovalOptions(isEnabled: true, tolerance: 0.16)
}

struct MenuBarIconContrastReport: Equatable {
    var lightContrast: Double?
    var darkContrast: Double?

    var warningText: String? {
        let threshold = 2.4
        let lightIsLow = lightContrast.map { $0 < threshold } ?? false
        let darkIsLow = darkContrast.map { $0 < threshold } ?? false

        switch (lightIsLow, darkIsLow) {
        case (true, true):
            return "当前图标在深浅色菜单栏里都可能不够清晰。"
        case (true, false):
            return "当前图标在浅色菜单栏里对比度可能偏低。"
        case (false, true):
            return "当前图标在深色菜单栏里对比度可能偏低。"
        case (false, false):
            return nil
        }
    }
}

enum MenuBarIconProcessing {
    static let maxAnimationFileSize = 5 * 1024 * 1024
    static let maxAnimationFrames = 24
    static let maxAnimationSourceFrames = 120
    static let animationFramesPerSecond: TimeInterval = 6
    static let maxSourcePixelArea = 1_600 * 1_600

    static let supportedImageContentTypes: [UTType] = [
        .png,
        .jpeg,
        .webP,
        .icns,
        .image
    ].compactMap { $0 }

    static let supportedAnimationContentTypes: [UTType] = [
        .gif,
        .mpeg4Movie,
        .quickTimeMovie,
        .movie
    ].compactMap { $0 }

    static func renderedImage(
        from image: NSImage,
        adjustment: MenuBarIconAdjustment,
        pointSize: CGFloat = 18,
        scaleFactor: CGFloat = 2
    ) -> NSImage? {
        guard let source = cgImage(from: image) else {
            return nil
        }

        let pixelSize = Int((pointSize * scaleFactor).rounded())
        guard pixelSize > 0 else {
            return nil
        }

        let canvasSize = CGSize(width: pixelSize, height: pixelSize)
        guard
            let context = CGContext(
                data: nil,
                width: pixelSize,
                height: pixelSize,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.clear(CGRect(origin: .zero, size: canvasSize))
        context.interpolationQuality = .high

        let sourceWidth = CGFloat(source.width)
        let sourceHeight = CGFloat(source.height)
        let baseScale = min(canvasSize.width / sourceWidth, canvasSize.height / sourceHeight)
        let renderScale = max(0.2, min(3, adjustment.scale)) * baseScale
        let drawWidth = sourceWidth * renderScale
        let drawHeight = sourceHeight * renderScale
        let originX = ((canvasSize.width - drawWidth) / 2) + (CGFloat(adjustment.offsetX) * scaleFactor)
        let originY = ((canvasSize.height - drawHeight) / 2) - (CGFloat(adjustment.offsetY) * scaleFactor)
        let drawSize = CGSize(width: drawWidth, height: drawHeight)
        let origin = CGPoint(
            x: originX,
            y: originY
        )

        context.draw(source, in: CGRect(origin: origin, size: drawSize))

        guard let rendered = context.makeImage() else {
            return nil
        }

        let output = NSImage(cgImage: rendered, size: NSSize(width: pointSize, height: pointSize))
        output.size = NSSize(width: pointSize, height: pointSize)
        return output
    }

    static func pngData(from image: NSImage) -> Data? {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    @MainActor
    static func animationFrameImages(from url: URL) async throws -> [NSImage] {
        guard isFileSizeAcceptable(url) else {
            throw MenuBarIconImportError.animationTooLarge
        }

        let contentType = contentType(for: url)
        if contentType?.conforms(to: .movie) == true || contentType?.conforms(to: .audiovisualContent) == true {
            return try await videoFrameImages(from: url)
        }

        if contentType?.conforms(to: .gif) == true || url.pathExtension.lowercased() == "gif" {
            return try imageSourceFrameImages(from: url)
        }

        throw MenuBarIconImportError.unsupportedAnimation
    }

    static func contrastReport(for image: NSImage?) -> MenuBarIconContrastReport {
        guard let image, let cgImage = cgImage(from: image) else {
            return MenuBarIconContrastReport(lightContrast: nil, darkContrast: nil)
        }

        guard let averageLuminance = averageVisibleLuminance(in: cgImage) else {
            return MenuBarIconContrastReport(lightContrast: nil, darkContrast: nil)
        }

        let lightMenuBarLuminance = 0.94
        let darkMenuBarLuminance = 0.08
        return MenuBarIconContrastReport(
            lightContrast: contrastRatio(averageLuminance, lightMenuBarLuminance),
            darkContrast: contrastRatio(averageLuminance, darkMenuBarLuminance)
        )
    }

    private static func averageVisibleLuminance(in image: CGImage) -> Double? {
        let width = 16
        let height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard
            let context = CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var weightedLuminance = 0.0
        var visibleWeight = 0.0

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.08 else {
                continue
            }

            let red = Double(pixels[index]) / 255
            let green = Double(pixels[index + 1]) / 255
            let blue = Double(pixels[index + 2]) / 255
            let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)

            weightedLuminance += luminance * alpha
            visibleWeight += alpha
        }

        guard visibleWeight > 0 else {
            return nil
        }

        return weightedLuminance / visibleWeight
    }

    private static func contrastRatio(_ first: Double, _ second: Double) -> Double {
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private static func isFileSizeAcceptable(_ url: URL) -> Bool {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return true
        }

        return fileSize <= maxAnimationFileSize
    }

    private static func contentType(for url: URL) -> UTType? {
        guard let values = try? url.resourceValues(forKeys: [.contentTypeKey]) else {
            return nil
        }

        return values.contentType ?? UTType(filenameExtension: url.pathExtension)
    }

    private static func imageSourceFrameImages(from url: URL) throws -> [NSImage] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw MenuBarIconImportError.cannotDecodeAnimation
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 1 else {
            throw MenuBarIconImportError.notAnimated
        }
        guard frameCount <= maxAnimationSourceFrames else {
            throw MenuBarIconImportError.animationTooComplex
        }

        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width * height > maxSourcePixelArea {
            throw MenuBarIconImportError.animationTooLarge
        }

        let targetCount = min(frameCount, maxAnimationFrames)
        let frameStep = max(1, Int(ceil(Double(frameCount) / Double(targetCount))))
        var frames: [NSImage] = []

        for index in stride(from: 0, to: frameCount, by: frameStep) where frames.count < maxAnimationFrames {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                continue
            }

            frames.append(NSImage(cgImage: frame, size: .zero))
        }

        guard frames.count > 1 else {
            throw MenuBarIconImportError.cannotDecodeAnimation
        }

        return frames
    }

    private static func imageSourceFrameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
            let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 1.0 / animationFramesPerSecond
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let delay = unclampedDelay ?? gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval
        return max(delay ?? (1.0 / animationFramesPerSecond), 0.02)
    }

    @MainActor
    private static func videoFrameImages(from url: URL) async throws -> [NSImage] {
        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let duration = CMTimeGetSeconds(durationTime)
        guard duration.isFinite, duration > 0 else {
            throw MenuBarIconImportError.cannotDecodeAnimation
        }

        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            let pixelArea = abs(transformedSize.width * transformedSize.height)
            guard pixelArea <= CGFloat(maxSourcePixelArea) else {
                throw MenuBarIconImportError.animationTooLarge
            }
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 256, height: 256)

        let frameCount = min(
            maxAnimationFrames,
            max(2, Int(ceil(duration * animationFramesPerSecond)))
        )
        var frames: [NSImage] = []

        for index in 0..<frameCount {
            let progress = frameCount == 1 ? 0 : Double(index) / Double(frameCount)
            let seconds = min(duration, progress * duration)
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            guard let frame = try? generator.copyCGImage(at: time, actualTime: nil) else {
                continue
            }

            frames.append(NSImage(cgImage: frame, size: .zero))
        }

        guard frames.count > 1 else {
            throw MenuBarIconImportError.cannotDecodeAnimation
        }

        return frames
    }
}

enum MenuBarIconImportError: Error {
    case animationTooLarge
    case animationTooComplex
    case cannotDecodeAnimation
    case notAnimated
    case unsupportedAnimation

    var userMessage: String {
        switch self {
        case .animationTooLarge:
            return "动画文件过大或分辨率过高，请选择 5 MB 以内、画面更简单的文件。"
        case .animationTooComplex:
            return "动画帧数过多，请选择更简单的短动画。"
        case .cannotDecodeAnimation:
            return "无法解析这个动画文件。"
        case .notAnimated:
            return "所选文件不是可循环播放的动画。"
        case .unsupportedAnimation:
            return "暂不支持这个动画格式，请选择 GIF 或 MP4。"
        }
    }
}

@MainActor
final class MenuBarIconSettings: ObservableObject {
    private enum DefaultsKey {
        static let storage = "menubar.icon.settings"
    }

    private struct StoredState: Codable, Equatable {
        var renderMode: MenuBarIconRenderMode = .template
        var animationSpeedMode: MenuBarIconAnimationSpeedMode = .manual
        var manualAnimationSpeedMultiplier: Double = MenuBarIconAnimationSpeedPolicy.defaultManualMultiplier
        var backgroundRemovalOptions: MenuBarIconBackgroundRemovalOptions = .default
        var lightIconFileName: String?
        var darkIconFileName: String?
        var lightAdjustment: MenuBarIconAdjustment = .default
        var darkAdjustment: MenuBarIconAdjustment = .default
        var recentItems: [MenuBarIconRecentItem] = []
    }

    private struct RenderedFramesCacheKey: Hashable {
        let id: UUID
        let fileName: String
        let frameFileNames: [String]
    }

    private struct RecentPreviewCacheKey: Hashable {
        let id: UUID
        let fileName: String
    }

    private static let defaultIconName = NSImage.Name("MenuBarIcon")
    private static let iconPointSize = NSSize(width: 18, height: 18)
    private static let maxRecentItems = 6

    @Published private var storedState: StoredState
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var settingsRevision: Int = 0

    private let userDefaults: UserDefaults
    private let fileManager: FileManager
    private let rootDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var imagePayloadCache: [MenuBarIconAppearance: MenuBarIconImagePayload] = [:]
    private var renderedFramesCache: [RenderedFramesCacheKey: [NSImage]] = [:]
    private var recentPreviewCache: [RecentPreviewCacheKey: NSImage] = [:]
    private var contrastReportCache: [MenuBarIconAppearance: MenuBarIconContrastReport] = [:]

    init(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        rootDirectory: URL? = nil
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? Self.defaultRootDirectory(fileManager: fileManager)
        self.storedState = Self.loadState(userDefaults: userDefaults)
        self.storedState.lightAdjustment = .default
        self.storedState.darkAdjustment = .default
        self.storedState.backgroundRemovalOptions = .default
        self.storedState.renderMode = .original
        pruneMissingRecentItems()
    }

    var renderMode: MenuBarIconRenderMode {
        get { storedState.renderMode }
        set {
            guard storedState.renderMode != newValue else {
                return
            }

            storedState.renderMode = newValue
            invalidateSelectedIconCaches()
            persist()
        }
    }

    var recentItems: [MenuBarIconRecentItem] {
        storedState.recentItems
    }

    var builtInAnimations: [MenuBarIconBuiltInAnimation] {
        MenuBarIconBuiltInAnimation.all
    }

    var animationSpeedMode: MenuBarIconAnimationSpeedMode {
        get { storedState.animationSpeedMode }
        set {
            guard storedState.animationSpeedMode != newValue else {
                return
            }

            storedState.animationSpeedMode = newValue
            invalidateImagePayloadCache()
            persist()
        }
    }

    var manualAnimationSpeedMultiplier: Double {
        get { storedState.manualAnimationSpeedMultiplier }
        set {
            let normalizedValue = MenuBarIconAnimationSpeedPolicy.normalizedManualMultiplier(newValue)
            guard storedState.manualAnimationSpeedMultiplier != normalizedValue else {
                return
            }

            storedState.manualAnimationSpeedMultiplier = normalizedValue
            invalidateImagePayloadCache()
            persist()
        }
    }

    var hasCustomIcon: Bool {
        storedState.lightIconFileName != nil || storedState.darkIconFileName != nil
    }

    func importIcon(from sourceURL: URL, for _: MenuBarIconAppearance) {
        importIcon(from: sourceURL)
    }

    func importIcon(from sourceURL: URL) {
        clearError()

        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
            lastErrorMessage = "无法读取所选图片。"
            return
        }
        let processedImage = MenuBarIconBackgroundRemover.removingBackground(
            from: sourceImage,
            options: .default
        ) ?? sourceImage

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        let recentFileName = "recent-\(UUID().uuidString).png"
        let recentURL = recentsDirectory.appendingPathComponent(recentFileName)

        guard saveOriginalImage(processedImage, to: recentURL) else {
            lastErrorMessage = "无法保存所选图片。"
            return
        }

        let recentItem = MenuBarIconRecentItem(
            id: UUID(),
            fileName: recentFileName,
            frameFileNames: [recentFileName],
            displayName: displayName.isEmpty ? "自定义图标" : displayName,
            addedAt: Date(),
            mediaKind: .image,
            frameDuration: 1.0 / MenuBarIconProcessing.animationFramesPerSecond
        )

        storeRecentItem(recentItem)
        setIconFileNameForAllAppearances(recentFileName)
        resetAdjustmentsForAllAppearances()
        invalidateAllIconCaches()
        persist()
    }

    func importAnimation(from sourceURL: URL, for _: MenuBarIconAppearance) async {
        await importAnimation(from: sourceURL)
    }

    func importAnimation(from sourceURL: URL) async {
        clearError()

        let sourceFrames: [NSImage]
        do {
            sourceFrames = try await MenuBarIconProcessing.animationFrameImages(from: sourceURL)
        } catch let error as MenuBarIconImportError {
            lastErrorMessage = error.userMessage
            return
        } catch {
            lastErrorMessage = "无法解析这个动画文件。"
            return
        }

        let animationID = UUID().uuidString
        let fileNames = sourceFrames.indices.map { index in
            "animation-\(animationID)-frame-\(index).png"
        }

        let processedFrames = sourceFrames.map { frame in
            MenuBarIconBackgroundRemover.removingBackground(
                from: frame,
                options: .default
            ) ?? frame
        }

        guard saveAnimationFrames(processedFrames, fileNames: fileNames) else {
            lastErrorMessage = "无法保存动画图标。"
            return
        }

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        let recentItem = MenuBarIconRecentItem(
            id: UUID(),
            fileName: fileNames[0],
            frameFileNames: fileNames,
            displayName: displayName.isEmpty ? "动画图标" : displayName,
            addedAt: Date(),
            mediaKind: .animation,
            frameDuration: 1.0 / MenuBarIconProcessing.animationFramesPerSecond
        )

        storeRecentItem(recentItem)
        setIconFileNameForAllAppearances(recentItem.fileName)
        resetAdjustmentsForAllAppearances()
        invalidateAllIconCaches()
        persist()
    }

    func useBuiltInAnimation(_ animation: MenuBarIconBuiltInAnimation, for _: MenuBarIconAppearance) {
        useBuiltInAnimation(animation)
    }

    func useBuiltInAnimation(_ animation: MenuBarIconBuiltInAnimation) {
        clearError()

        let sourceFrames = animation.loadFrames()
        guard sourceFrames.count > 1 else {
            lastErrorMessage = "无法读取内置动画素材。"
            return
        }

        let animationID = "builtin-\(animation.id)-\(UUID().uuidString)"
        let fileNames = sourceFrames.indices.map { index in
            "\(animationID)-frame-\(index).png"
        }

        guard saveAnimationFrames(sourceFrames, fileNames: fileNames) else {
            lastErrorMessage = "无法保存内置动画。"
            return
        }

        let recentItem = MenuBarIconRecentItem(
            id: UUID(),
            fileName: fileNames[0],
            frameFileNames: fileNames,
            displayName: animation.displayName,
            addedAt: Date(),
            mediaKind: .animation,
            frameDuration: animation.frameDuration
        )

        storeRecentItem(recentItem)
        setIconFileNameForAllAppearances(recentItem.fileName)
        resetAdjustmentsForAllAppearances()
        invalidateAllIconCaches()
        persist()
    }

    func useRecentIcon(_ item: MenuBarIconRecentItem, for _: MenuBarIconAppearance) {
        useRecentIcon(item)
    }

    func useRecentIcon(_ item: MenuBarIconRecentItem) {
        let requiredFileNames = item.mediaKind == .animation ? item.frameFileNames : [item.fileName]
        guard requiredFileNames.allSatisfy({ fileManager.fileExists(atPath: recentsDirectory.appendingPathComponent($0).path) }) else {
            lastErrorMessage = "最近使用的图标文件已不存在。"
            pruneMissingRecentItems()
            return
        }

        setIconFileNameForAllAppearances(item.fileName)
        resetAdjustmentsForAllAppearances()
        invalidateSelectedIconCaches()
        persist()
    }

    func resetToDefault() {
        storedState.lightIconFileName = nil
        storedState.darkIconFileName = nil
        storedState.lightAdjustment = .default
        storedState.darkAdjustment = .default
        invalidateSelectedIconCaches()
        persist()
    }

    func imagePayload(for appearance: NSAppearance? = nil) -> MenuBarIconImagePayload {
        let resolvedAppearance = resolvedAppearance(from: appearance)
        return imagePayload(for: resolvedAppearance)
    }

    func previewImage(for appearance: MenuBarIconAppearance) -> NSImage {
        imagePayload(for: appearance).image
    }

    func previewImage(for recentItem: MenuBarIconRecentItem) -> NSImage {
        let cacheKey = RecentPreviewCacheKey(id: recentItem.id, fileName: recentItem.fileName)
        if let cachedImage = recentPreviewCache[cacheKey] {
            return cachedImage
        }

        let image = renderedImage(fileName: recentItem.fileName) ?? Self.defaultImage()
        recentPreviewCache[cacheKey] = image
        return image
    }

    func previewImage(for builtInAnimation: MenuBarIconBuiltInAnimation) -> NSImage {
        guard
            let sourceImage = builtInAnimation.loadFirstFrame(),
            let image = MenuBarIconProcessing.renderedImage(from: sourceImage, adjustment: .default)
        else {
            return Self.defaultImage()
        }

        return image
    }

    func contrastReport(for appearance: MenuBarIconAppearance) -> MenuBarIconContrastReport {
        if let cachedReport = contrastReportCache[appearance] {
            return cachedReport
        }

        let report = MenuBarIconProcessing.contrastReport(for: previewImage(for: appearance))
        contrastReportCache[appearance] = report
        return report
    }

    func clearError() {
        lastErrorMessage = nil
    }

    private func imagePayload(for resolvedAppearance: MenuBarIconAppearance) -> MenuBarIconImagePayload {
        if let cachedPayload = imagePayloadCache[resolvedAppearance] {
            return cachedPayload
        }

        let payload = makeImagePayload(for: resolvedAppearance)
        imagePayloadCache[resolvedAppearance] = payload
        return payload
    }

    private func makeImagePayload(for resolvedAppearance: MenuBarIconAppearance) -> MenuBarIconImagePayload {
        guard let item = selectedRecentItem(for: resolvedAppearance) else {
            let image = Self.defaultImage()
            image.isTemplate = true
            return MenuBarIconImagePayload(
                image: image,
                isTemplate: true,
                animationFrames: [image],
                frameDuration: 1.0 / MenuBarIconProcessing.animationFramesPerSecond,
                speedMode: animationSpeedMode,
                manualSpeedMultiplier: manualAnimationSpeedMultiplier
            )
        }

        let frames = renderedImages(for: item)
        guard let image = frames.first else {
            let image = Self.defaultImage()
            image.isTemplate = true
            return MenuBarIconImagePayload(
                image: image,
                isTemplate: true,
                animationFrames: [image],
                frameDuration: 1.0 / MenuBarIconProcessing.animationFramesPerSecond,
                speedMode: animationSpeedMode,
                manualSpeedMultiplier: manualAnimationSpeedMultiplier
            )
        }

        image.isTemplate = false
        for frame in frames {
            frame.isTemplate = image.isTemplate
        }

        return MenuBarIconImagePayload(
            image: image,
            isTemplate: image.isTemplate,
            animationFrames: frames,
            frameDuration: item.frameDuration,
            speedMode: animationSpeedMode,
            manualSpeedMultiplier: manualAnimationSpeedMultiplier
        )
    }

    private var iconsDirectory: URL {
        rootDirectory.appendingPathComponent("MenuBarIcons", isDirectory: true)
    }

    private var recentsDirectory: URL {
        iconsDirectory.appendingPathComponent("Recents", isDirectory: true)
    }

    private static func defaultRootDirectory(fileManager: FileManager) -> URL {
        AppStorageScope.applicationSupportRoot(fileManager: fileManager)
    }

    private static func loadState(userDefaults: UserDefaults) -> StoredState {
        guard let data = userDefaults.data(forKey: DefaultsKey.storage) else {
            return StoredState()
        }

        do {
            return try JSONDecoder().decode(StoredState.self, from: data)
        } catch {
            userDefaults.removeObject(forKey: DefaultsKey.storage)
            return StoredState()
        }
    }

    private static func defaultImage() -> NSImage {
        let image = NSImage(named: defaultIconName) ?? NSImage(size: iconPointSize)
        image.size = iconPointSize
        return image
    }

    private func persist() {
        guard let data = try? encoder.encode(storedState) else {
            return
        }

        userDefaults.set(data, forKey: DefaultsKey.storage)
        settingsRevision += 1
    }

    private func selectedRecentItem(for appearance: MenuBarIconAppearance) -> MenuBarIconRecentItem? {
        guard let selection = iconSelection(for: appearance) else {
            return nil
        }

        return storedState.recentItems.first { item in
            item.fileName == selection.fileName
        }
    }

    private func renderedImages(for item: MenuBarIconRecentItem) -> [NSImage] {
        let cacheKey = RenderedFramesCacheKey(
            id: item.id,
            fileName: item.fileName,
            frameFileNames: item.frameFileNames
        )
        if let cachedImages = renderedFramesCache[cacheKey] {
            return cachedImages
        }

        let frameFileNames = item.mediaKind == .animation ? item.frameFileNames : [item.fileName]
        let images = frameFileNames.compactMap(renderedImage(fileName:))
        renderedFramesCache[cacheKey] = images
        return images
    }

    private func renderedImage(fileName: String) -> NSImage? {
        let url = recentsDirectory.appendingPathComponent(fileName)
        guard let sourceImage = NSImage(contentsOf: url) else {
            return nil
        }

        let image = MenuBarIconProcessing.renderedImage(
            from: sourceImage,
            adjustment: .default
        ) ?? sourceImage
        image.size = Self.iconPointSize
        return image
    }

    private func iconSelection(for appearance: MenuBarIconAppearance) -> (fileName: String, appearance: MenuBarIconAppearance)? {
        switch appearance {
        case .light:
            return storedState.lightIconFileName.map { (fileName: $0, appearance: .light) }
        case .dark:
            if let darkIconFileName = storedState.darkIconFileName {
                return (fileName: darkIconFileName, appearance: .dark)
            }

            return storedState.lightIconFileName.map { (fileName: $0, appearance: .light) }
        }
    }

    private func storeRecentItem(_ recentItem: MenuBarIconRecentItem) {
        storedState.recentItems.removeAll { item in
            item.fileName == recentItem.fileName || item.displayName == recentItem.displayName
        }
        storedState.recentItems.insert(recentItem, at: 0)
        storedState.recentItems = Array(storedState.recentItems.prefix(Self.maxRecentItems))
    }

    private func setIconFileNameForAllAppearances(_ fileName: String?) {
        storedState.lightIconFileName = fileName
        storedState.darkIconFileName = fileName
    }

    private func resetAdjustmentsForAllAppearances() {
        storedState.lightAdjustment = .default
        storedState.darkAdjustment = .default
    }

    private func saveOriginalImage(_ image: NSImage, to destinationURL: URL) -> Bool {
        guard let data = MenuBarIconProcessing.pngData(from: image) else {
            return false
        }

        do {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: destinationURL, options: .atomic)
            return true
        } catch {
            lastErrorMessage = "无法保存图标设置。"
            return false
        }
    }

    private func saveAnimationFrames(_ frames: [NSImage], fileNames: [String]) -> Bool {
        guard frames.count == fileNames.count, !frames.isEmpty else {
            return false
        }

        do {
            try fileManager.createDirectory(at: recentsDirectory, withIntermediateDirectories: true)
            for (frame, fileName) in zip(frames, fileNames) {
                guard let data = MenuBarIconProcessing.pngData(from: frame) else {
                    return false
                }

                let destinationURL = recentsDirectory.appendingPathComponent(fileName)
                try data.write(to: destinationURL, options: .atomic)
            }

            return true
        } catch {
            lastErrorMessage = "无法保存动画图标。"
            return false
        }
    }

    private func resolvedAppearance(from appearance: NSAppearance?) -> MenuBarIconAppearance {
        let bestMatch = (appearance ?? NSApp.effectiveAppearance).bestMatch(from: [.darkAqua, .aqua])
        return bestMatch == .darkAqua ? .dark : .light
    }

    private func pruneMissingRecentItems() {
        let items = storedState.recentItems.filter { item in
            let requiredFileNames = item.mediaKind == .animation ? item.frameFileNames : [item.fileName]
            return requiredFileNames.allSatisfy { fileName in
                fileManager.fileExists(atPath: recentsDirectory.appendingPathComponent(fileName).path)
            }
        }

        guard items != storedState.recentItems else {
            return
        }

        storedState.recentItems = items
        invalidateAllIconCaches()
        persist()
    }

    private func invalidateImagePayloadCache() {
        imagePayloadCache.removeAll()
    }

    private func invalidateSelectedIconCaches() {
        imagePayloadCache.removeAll()
        contrastReportCache.removeAll()
    }

    private func invalidateAllIconCaches() {
        invalidateSelectedIconCaches()
        renderedFramesCache.removeAll()
        recentPreviewCache.removeAll()
    }
}
