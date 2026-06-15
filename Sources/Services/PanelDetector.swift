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

        // ── 2. Determine if background is dark or light, and define gutter test ─
        let isDarkBg = isPageBackgroundDark(raw: raw, W: W, H: H, bpr: bpr, bpp: bpp)

        func isGutter(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < W, y >= 0, y < H else { return true }
            let o = y * bpr + x * bpp
            let r = Double(raw[o])
            let g = Double(raw[o+1])
            let b = Double(raw[o+2])
            
            if isDarkBg {
                let tol = 50.0
                return r < tol && g < tol && b < tol
            } else {
                let threshold = 205.0
                return r > threshold && g > threshold && b > threshold
            }
        }

        // ── 3. Build gutter mask (work at reduced resolution for speed) ───────
        // We downsample to at most 1024 pixels on the long side to keep thin borders intact and processing fast.
        let scale = min(1.0, 1024.0 / Double(max(W, H)))
        let mW = max(4, Int(Double(W) * scale))
        let mH = max(4, Int(Double(H) * scale))

        // mask[y*mW + x] = true → gutter, false → artwork
        var mask = [Bool](repeating: false, count: mW * mH)
        for my in 0..<mH {
            for mx in 0..<mW {
                let px = Int(Double(mx) / scale)
                let py = Int(Double(my) / scale)
                mask[my * mW + mx] = isGutter(px, py)
            }
        }

        // ── 4. Flood-fill connected artwork (non-gutter) regions ─────────────
        var labels = [Int](repeating: -1, count: mW * mH)  // -1 = unlabeled
        var regionBounds: [(minX: Int, minY: Int, maxX: Int, maxY: Int)] = []
        var labelCounter = 0

        for startY in 0..<mH {
            for startX in 0..<mW {
                let startIdx = startY * mW + startX
                guard !mask[startIdx], labels[startIdx] == -1 else { continue }

                // BFS flood fill
                let label = labelCounter
                labelCounter += 1
                regionBounds.append((startX, startY, startX, startY))

                var queue = [(startX, startY)]
                labels[startIdx] = label
                var head = 0

                while head < queue.count {
                    let (cx, cy) = queue[head]; head += 1
                    // Update bounding box
                    if cx < regionBounds[label].minX { regionBounds[label].minX = cx }
                    if cx > regionBounds[label].maxX { regionBounds[label].maxX = cx }
                    if cy < regionBounds[label].minY { regionBounds[label].minY = cy }
                    if cy > regionBounds[label].maxY { regionBounds[label].maxY = cy }

                    // 4-connected neighbors
                    for (nx, ny) in [(cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)] {
                        guard nx >= 0, nx < mW, ny >= 0, ny < mH else { continue }
                        let nIdx = ny * mW + nx
                        guard !mask[nIdx], labels[nIdx] == -1 else { continue }
                        labels[nIdx] = label
                        queue.append((nx, ny))
                    }
                }
            }
        }

        // ── 5. Filter out tiny regions (noise) and convert to normalized rects ─
        let minArea = Double(mW * mH) * 0.015   // region must be ≥1.5% of page
        let maxArea = Double(mW * mH) * 0.97    // not the whole page

        var rects: [CGRect] = []
        for (_, b) in regionBounds.enumerated() {
            let w = b.maxX - b.minX + 1
            let h = b.maxY - b.minY + 1
            let area = Double(w * h)
            guard area >= minArea, area <= maxArea else { continue }

            // Convert mask coordinates back to normalized [0,1]
            let nX = Double(b.minX) / Double(mW)
            let nY = Double(b.minY) / Double(mH)
            let nW = Double(w) / Double(mW)
            let nH = Double(h) / Double(mH)
            rects.append(CGRect(x: nX, y: nY, width: nW, height: nH))
        }

        guard !rects.isEmpty else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        // ── 6. Sort by reading order ──────────────────────────────────────────
        return sortRects(rects, direction: direction)
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

    private static func isPageBackgroundDark(raw: [UInt8], W: Int, H: Int, bpr: Int, bpp: Int) -> Bool {
        var brightnesses: [Double] = []
        
        func sample(_ x: Int, _ y: Int) {
            guard x >= 0, x < W, y >= 0, y < H else { return }
            let o = y * bpr + x * bpp
            guard o + 2 < raw.count else { return }
            let r = Double(raw[o])
            let g = Double(raw[o+1])
            let b = Double(raw[o+2])
            brightnesses.append((r + g + b) / 3.0)
        }
        
        let xStep = max(1, W / 60), yStep = max(1, H / 60)
        for x in stride(from: 0, to: W, by: xStep) {
            for d in 0...4 { sample(x, d); sample(x, H-1-d) }
        }
        for y in stride(from: 0, to: H, by: yStep) {
            for d in 0...4 { sample(d, y); sample(W-1-d, y) }
        }
        
        guard !brightnesses.isEmpty else { return false }
        brightnesses.sort()
        return brightnesses[brightnesses.count / 2] < 80.0
    }
}
