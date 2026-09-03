/// A bounded summary of additive color that can escape a foreground's alpha
/// through content blur, including emission carried by used bitmap payloads.
/// No GPU texture pixels or renderer state are read.
struct SceneAdditiveEmissionAnalysis {
    /// Additive delta can enter this target's F plane if it is backdrop-isolated.
    /// An independent child resolves its own ordinary target, so it is a boundary.
    var sharedAdditive = false
    /// A reachable isolated blur or bitmap can carry RGB above its alpha.
    var escapedEmission = false
    var exceedsLimit = false
    var invalidBitmapDefect: String?

    private struct Budget {
        // The filtered pass itself consumes one namespace and one depth level.
        var remainingPasses = GPUISceneLimits.maxImageRenderPassCount - 1
        // At most 64 MiB of actual BGRA8 texels per query, excluding padding.
        // Sharing the content cache across namespaces avoids rescanning cached
        // rasterizer output; mutation and geometry changes produce a new key.
        var remainingBitmapPixels = GPUISceneLimits.maxImageRenderPassTotalPixels
        var bitmapEmission: [BitmapContentKey: Bool] = [:]
    }

    static func inspect(_ scene: GPUIScene) -> Self {
        var budget = Budget()
        return inspect(scene, depth: 1, budget: &budget)
    }

    private static func inspect(
        _ scene: GPUIScene, depth: Int, budget: inout Budget
    ) -> Self {
        guard depth <= GPUISceneLimits.maxImageRenderPassDepth,
            scene.imageRenderPasses.count <= GPUISceneLimits.maxImageRenderPassCount
        else { return limited() }

        let bitmaps = Dictionary(
            scene.imageResources.map { ($0.textureID, $0.bitmap) },
            uniquingKeysWith: { _, last in last })
        let passes = Dictionary(
            scene.imageRenderPasses.map { ($0.textureID, $0) },
            uniquingKeysWith: { _, last in last })
        // IDs belong to this namespace, not the whole tree. Repeated consumers
        // reuse this structural result even though dependent pixels are redrawn.
        var children: [Int32: Self] = [:]
        var result = Self()
        for run in scene.presentationOrder() {
            let layer = scene.layers[run.layerIndex]
            switch run.kind {
            case .quad:
                for index in run.range {
                    let quad = layer.quads[index]
                    // Match the ordinary/material dispatch boundary exactly.
                    if quad.blendMode == Float(BlendMode.additive.rawValue),
                        GPUISceneValue.int(quad.blurRadius) <= 0
                    {
                        result.sharedAdditive = true
                    }
                }
            case .image:
                for index in run.range {
                    let textureID = layer.images[index].textureID
                    if let bitmap = bitmaps[textureID] {
                        let child: Self
                        if let cached = children[textureID] {
                            child = cached
                        } else {
                            child = inspect(bitmap, budget: &budget)
                            children[textureID] = child
                        }
                        if child.exceedsLimit || child.invalidBitmapDefect != nil { return child }
                        result.escapedEmission = result.escapedEmission || child.escapedEmission
                        continue
                    }
                    guard let pass = passes[textureID] else { continue }
                    let child: Self
                    if let cached = children[textureID] {
                        child = cached
                    } else {
                        guard depth < GPUISceneLimits.maxImageRenderPassDepth, budget.remainingPasses > 0 else {
                            return limited()
                        }
                        budget.remainingPasses -= 1
                        child = inspect(pass.scene, depth: depth + 1, budget: &budget)
                        children[textureID] = child
                    }
                    if child.exceedsLimit || child.invalidBitmapDefect != nil { return child }
                    result.escapedEmission = result.escapedEmission || child.escapedEmission
                    if pass.input != .independent {
                        result.sharedAdditive = result.sharedAdditive || child.sharedAdditive
                        if pass.input == .isolatedBackdrop, pass.contentBlurRadius > 0, child.sharedAdditive {
                            result.escapedEmission = true
                        }
                    }
                }
            case .shadow, .glyph, .pixelGlyph, .path:
                break
            }
        }
        return result
    }

    private static func inspect(_ bitmap: BitmapSurface, budget: inout Budget) -> Self {
        // Straight bytes become representable during the existing upload or
        // CPU conversion. Only already-premultiplied payloads can carry RGB>A.
        guard bitmap.format.alphaMode == .premultiplied else { return Self() }
        if let emitted = budget.bitmapEmission[bitmap.contentKey] {
            var result = Self()
            result.escapedEmission = emitted
            return result
        }
        // GPU upload rejects malformed storage, but the CPU can draw its valid
        // prefix. Refuse this used effect source explicitly rather than call
        // an unscannable prefix safe or mislabel it as budget exhaustion.
        do { try bitmap.validate() } catch {
            var result = Self()
            result.invalidBitmapDefect = "post-filter source uses an invalid premultiplied bitmap: \(error)"
            return result
        }
        let pixelCount = Int(bitmap.width) * Int(bitmap.height)
        guard pixelCount <= budget.remainingBitmapPixels else { return limited() }
        budget.remainingBitmapPixels -= pixelCount
        let emitted = bitmap.pixels.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            for y in 0..<Int(bitmap.height) {
                let row = y * Int(bitmap.bytesPerRow)
                for x in 0..<Int(bitmap.width) {
                    let offset = row + x * 4
                    let alpha = buffer[offset + 3]
                    if buffer[offset] > alpha || buffer[offset + 1] > alpha || buffer[offset + 2] > alpha {
                        return true
                    }
                }
            }
            return false
        }
        budget.bitmapEmission[bitmap.contentKey] = emitted
        var result = Self()
        result.escapedEmission = emitted
        return result
    }

    private static func limited() -> Self {
        var result = Self()
        result.exceedsLimit = true
        return result
    }
}
