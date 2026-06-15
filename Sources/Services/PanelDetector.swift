import Foundation
import CoreGraphics

/// PanelDetector: Detects comic panels by segmenting a page along its white gutter regions.
///
/// Algorithm:
/// 1. Detect the gutter (background) color from outer page edges.
/// 2. Build a binary gutter mask (every pixel is gutter or artwork).
/// 3. Flood-fill connected artwork regions — each region is a panel.
/// 4. Return the bounding box of each region larger than a minimum size.
@preconcurrency import Vision

public class PanelDetector {

    public static func detectPanels(in cgImage: CGImage, direction: ReadingDirection = .leftToRight) async -> [CGRect] {

        // ── 1. Rasterize image into RGBA bitmap ───────────────────────────────
        let W = cgImage.width, H = cgImage.height
        guard W > 4, H > 4 else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let bpp = 4, bpr = bpp * W
        var raw = [UInt8](repeating: 0, count: H * bpr)
        guard let ctx = CGContext(data: &raw, width: W, height: H,
                                   bitsPerComponent: 8, bytesPerRow: bpr,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return [CGRect(x: 0, y: 0, width: 1, height: 1)] }
        // Flip Y so buffer row 0 = visual top of image
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: W, height: H))

        // ── 2. Determine median edge background color and gutter test ─────────
        let bg = detectMedianEdgeColor(raw: raw, W: W, H: H, bpr: bpr, bpp: bpp)

        func isGutter(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < W, y >= 0, y < H else { return true }
            let o = y * bpr + x * bpp
            let r = Double(raw[o])
            let g = Double(raw[o+1])
            let b = Double(raw[o+2])
            
            if bg.isDark {
                // For dark background, the gutter is black/near-black
                let tol = 50.0
                return r < tol && g < tol && b < tol
            } else {
                // For light background, the gutter is white/near-white
                let whiteTol = 45.0
                return abs(r - bg.r) < whiteTol
                    && abs(g - bg.g) < whiteTol
                    && abs(b - bg.b) < whiteTol
            }
        }

        // ── 3. Build gutter mask (work at reduced resolution for speed) ───────
        // We downsample to at most 1024 pixels on the long side to keep thin borders intact and processing fast.
        let scale = min(1.0, 1024.0 / Double(max(W, H)))
        let mW = max(4, Int(Double(W) * scale))
        let mH = max(4, Int(Double(H) * scale))

        // mask[y*mW + x] = true → wall (gutter or border), false → empty/artwork
        var mask = [Bool](repeating: false, count: mW * mH)
        for my in 0..<mH {
            for mx in 0..<mW {
                let px = Int(Double(mx) / scale)
                let py = Int(Double(my) / scale)
                mask[my * mW + mx] = isGutter(px, py)
            }
        }

        // ── 4. Morphological Dilation on borders ──────────────────────────────
        // Expand the wall pixels slightly to seal any small scan gaps in outlines.
        var dilatedMask = mask
        for my in 1..<(mH - 1) {
            for mx in 1..<(mW - 1) {
                if mask[my * mW + mx] { continue }
                // 3x3 neighborhood check
                let neighbors = [
                    (my-1)*mW + (mx-1), (my-1)*mW + mx, (my-1)*mW + (mx+1),
                    my*mW + (mx-1),                    my*mW + (mx+1),
                    (my+1)*mW + (mx-1), (my+1)*mW + mx, (my+1)*mW + (mx+1)
                ]
                for idx in neighbors {
                    if mask[idx] {
                        dilatedMask[my * mW + mx] = true
                        break
                    }
                }
            }
        }
        mask = dilatedMask

        // ── 5. Flood-fill connected artwork regions ──────────────────────────
        var labels = [Int](repeating: -1, count: mW * mH)
        var regionBounds: [(minX: Int, minY: Int, maxX: Int, maxY: Int, area: Int)] = []
        var labelCounter = 0

        for startY in 0..<mH {
            for startX in 0..<mW {
                let startIdx = startY * mW + startX
                guard !mask[startIdx], labels[startIdx] == -1 else { continue }

                let label = labelCounter
                labelCounter += 1
                regionBounds.append((startX, startY, startX, startY, 0))

                var queue = [startIdx]
                labels[startIdx] = label
                var head = 0

                while head < queue.count {
                    let currIdx = queue[head]; head += 1
                    let cx = currIdx % mW
                    let cy = currIdx / mW
                    
                    regionBounds[label].area += 1
                    if cx < regionBounds[label].minX { regionBounds[label].minX = cx }
                    if cx > regionBounds[label].maxX { regionBounds[label].maxX = cx }
                    if cy < regionBounds[label].minY { regionBounds[label].minY = cy }
                    if cy > regionBounds[label].maxY { regionBounds[label].maxY = cy }

                    // 4-connected neighbors
                    for (nx, ny) in [(cx-1, cy), (cx+1, cy), (cx, cy-1), (cx, cy+1)] {
                        guard nx >= 0, nx < mW, ny >= 0, ny < mH else { continue }
                        let nIdx = ny * mW + nx
                        guard !mask[nIdx], labels[nIdx] == -1 else { continue }
                        labels[nIdx] = label
                        queue.append(nIdx)
                    }
                }
            }
        }

        // ── 6. Convert & Filter Bounding Contours ─────────────────────────────
        var candidates: [CGRect] = []
        let totalPixels = Double(mW * mH)
        let minArea = totalPixels * 0.025   // must occupy at least 2.5% of the page to filter tiny text blocks
        let maxArea = totalPixels * 0.95   // cannot occupy more than 95% of the page

        for b in regionBounds {
            let w = b.maxX - b.minX + 1
            let h = b.maxY - b.minY + 1
            let area = Double(w * h)
            
            // Reject if too small or too large
            guard area >= minArea, area <= maxArea else { continue }
            
            // Aspect ratio check: reject extreme rectangular lines/strips
            let aspect = Double(w) / Double(h)
            guard aspect >= 0.1, aspect <= 10.0 else { continue }
            
            // Convert to normalized coordinates [0.0, 1.0]
            let nX = Double(b.minX) / Double(mW)
            let nY = Double(b.minY) / Double(mH)
            let nW = Double(w) / Double(mW)
            let nH = Double(h) / Double(mH)
            candidates.append(CGRect(x: nX, y: nY, width: nW, height: nH))
        }

        // --- Filter 1: Handle nested panels (giant container vs detail/text sub-regions) ---
        var toReject = Set<Int>()
        for i in 0..<candidates.count {
            let rectA = candidates[i]
            let areaA = rectA.width * rectA.height
            
            var childrenIndices: [Int] = []
            for j in 0..<candidates.count {
                if i == j { continue }
                let rectB = candidates[j]
                
                // Is rectB fully inside rectA (with 0.01 margin)?
                let isInside = rectB.minX >= rectA.minX - 0.01 &&
                               rectB.maxX <= rectA.maxX + 0.01 &&
                               rectB.minY >= rectA.minY - 0.01 &&
                               rectB.maxY <= rectA.maxY + 0.01
                
                let isSmaller = (rectB.width * rectB.height) < areaA * 0.9
                
                if isInside && isSmaller {
                    childrenIndices.append(j)
                }
            }
            
            if !childrenIndices.isEmpty {
                // rectA contains nested regions.
                if areaA > 0.60 && childrenIndices.count >= 2 {
                    // rectA is a giant outer container wrapping actual panels. Reject the container.
                    toReject.insert(i)
                } else {
                    // rectA is a normal panel containing text or minor details. Reject all children.
                    for childIdx in childrenIndices {
                        toReject.insert(childIdx)
                    }
                }
            }
        }
        
        var filtered: [CGRect] = []
        for i in 0..<candidates.count {
            if !toReject.contains(i) {
                filtered.append(candidates[i])
            }
        }

        // --- Filter 2: Reject heavily overlapping duplicate regions ---
        var finalRects: [CGRect] = []
        // Sort from smallest to largest area (prefer tighter, smaller panel boundaries)
        let sortedCandidates = filtered.sorted { ($0.width * $0.height) < ($1.width * $1.height) }
        
        for rect in sortedCandidates {
            var shouldKeep = true
            for existing in finalRects {
                let intersection = rect.intersection(existing)
                if !intersection.isNull {
                    let interArea = intersection.width * intersection.height
                    let minArea = min(rect.width * rect.height, existing.width * existing.height)
                    
                    // If overlapping area is more than 80% of the smaller box area, it's a duplicate
                    if interArea / minArea > 0.8 {
                        shouldKeep = false
                        break
                    }
                }
            }
            if shouldKeep {
                finalRects.append(rect)
            }
        }

        guard !finalRects.isEmpty else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        // ── 7. Sort by reading order ──────────────────────────────────────────
        return sortRects(finalRects, direction: direction)
    }

    // MARK: - Helpers

    public static func sortRects(_ rects: [CGRect], direction: ReadingDirection) -> [CGRect] {
        guard rects.count > 1 else { return rects }

        let avgHeight = rects.reduce(0.0) { $0 + $1.height } / CGFloat(rects.count)
        let rowThreshold = max(0.04, avgHeight * 0.5)

        var rows: [[CGRect]] = []
        var remaining = rects.sorted { $0.origin.y < $1.origin.y }

        while !remaining.isEmpty {
            let pivot = remaining.removeFirst()
            var currentRow = [pivot]
            remaining = remaining.filter { rect in
                if abs(rect.midY - pivot.midY) < rowThreshold {
                    currentRow.append(rect)
                    return false
                }
                return true
            }
            currentRow.sort { direction == .leftToRight ? $0.origin.x < $1.origin.x : $0.origin.x > $1.origin.x }
            rows.append(currentRow)
        }

        return rows.flatMap { $0 }
    }

    private static func detectMedianEdgeColor(raw: [UInt8], W: Int, H: Int, bpr: Int, bpp: Int) -> (r: Double, g: Double, b: Double, isDark: Bool) {
        var rs: [Double] = [], gs: [Double] = [], bs: [Double] = []
        
        // Sample 1.5% inward from the edges to bypass outer scanner black lines/borders
        let edgeOffsetX = max(5, Int(Double(W) * 0.015))
        let edgeOffsetY = max(5, Int(Double(H) * 0.015))
        
        func sample(_ x: Int, _ y: Int) {
            guard x >= 0, x < W, y >= 0, y < H else { return }
            let o = y * bpr + x * bpp
            guard o + 2 < raw.count else { return }
            rs.append(Double(raw[o]))
            gs.append(Double(raw[o+1]))
            bs.append(Double(raw[o+2]))
        }
        
        let xStep = max(1, W / 60), yStep = max(1, H / 60)
        for x in stride(from: 0, to: W, by: xStep) {
            for d in 0...4 {
                sample(x, edgeOffsetY + d)
                sample(x, H - 1 - edgeOffsetY - d)
            }
        }
        for y in stride(from: 0, to: H, by: yStep) {
            for d in 0...4 {
                sample(edgeOffsetX + d, y)
                sample(W - 1 - edgeOffsetX - d, y)
            }
        }
        
        guard !rs.isEmpty else { return (240, 240, 240, false) }
        rs.sort(); gs.sort(); bs.sort()
        
        let mid = rs.count / 2
        let medianR = rs[mid]
        let medianG = gs[mid]
        let medianB = bs[mid]
        let brightness = (medianR + medianG + medianB) / 3.0
        
        return (medianR, medianG, medianB, brightness < 100.0)
    }
}
