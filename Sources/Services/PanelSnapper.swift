import CoreGraphics
import Foundation

/// PanelSnapper: Finds the exact polygon boundary of a comic panel by scanning
/// **inward from outside** the panel's approximate boundary for each row.
///
/// For each row y in the panel's vertical range:
///   1. Interpolate where the initial polygon's left and right edges are at row y.
///   2. Start slightly OUTSIDE those edges (in the white gutter).
///   3. Scan inward until the first non-gutter pixel — that's the panel border.
///
/// This approach is immune to white text, speech bubbles, and bright highlights
/// inside the panel, because we only ever scan through the gutter, never through
/// the panel artwork itself.
///
/// Slanted panels are handled naturally: the per-row right/left edges trace the
/// diagonal, and top-band vs bottom-band averages give the 4 polygon corners.
public class PanelSnapper {

    // MARK: - Public API

    public static func snapPoints(
        _ points: [CGPoint],
        in cgImage: CGImage
    ) -> [CGPoint] {
        guard points.count == 4 else { return points }

        let W = cgImage.width, H = cgImage.height
        guard W > 4, H > 4 else { return points }

        let bpp = 4, bpr = bpp * W
        var raw = [UInt8](repeating: 0, count: H * bpr)

        guard let ctx = CGContext(
            data: &raw, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return points }

        // Core Graphics has Y=0 at the BOTTOM by default.
        // Apply a flip transform so the image is drawn top-down into the buffer:
        //   buffer row 0 = visual top of image (ny=0)
        //   buffer row H-1 = visual bottom of image (ny=1)
        // Without this, all y-coordinate lookups read the wrong rows (upside-down).
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: W, height: H))

        // ── 1. Determine if background is dark or light, and define gutter test ─
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

        // ── 2. Polygon corners in pixel space ─────────────────────────────────
        // Input order: [TL, TR, BR, BL]
        let tl = CGPoint(x: points[0].x * Double(W), y: points[0].y * Double(H))
        let tr = CGPoint(x: points[1].x * Double(W), y: points[1].y * Double(H))
        let br = CGPoint(x: points[2].x * Double(W), y: points[2].y * Double(H))
        let bl = CGPoint(x: points[3].x * Double(W), y: points[3].y * Double(H))

        let topY = Int(min(tl.y, tr.y))
        let botY = Int(max(bl.y, br.y))
        guard topY < botY else { return points }

        // ── 3. Linear interpolation along polygon left/right edges ────────────
        // Left  edge: TL→BL   Right edge: TR→BR
        func lerpX(_ y: Int, from p0: CGPoint, to p1: CGPoint) -> Int {
            guard p1.y > p0.y else { return Int(p0.x) }
            let t = (Double(y) - p0.y) / (p1.y - p0.y)
            return Int(p0.x + t * (p1.x - p0.x))
        }

        // ── 4. Per-row scan: find left and right artwork edges using transition-based matching ─
        // We look for the exact transition between gutter and artwork in a narrow search window.
        // This is extremely robust and prevents drifting or merging into adjacent panels.
        let scanWidth = max(15, Int(Double(W) * 0.02)) // 2% of width as search window
        let scanHeight = max(15, Int(Double(H) * 0.02)) // 2% of height as search window

        var rowLeftEdge  = [Int](repeating: -1, count: H)
        var rowRightEdge = [Int](repeating: -1, count: H)

        for y in topY...botY {
            let polyLeft  = lerpX(y, from: tl, to: bl)
            let polyRight = lerpX(y, from: tr, to: br)

            // --- Left edge: find transition from gutter (true) to artwork (false) ---
            let scanLStart = max(0, polyLeft - scanWidth)
            let scanLEnd   = min(W - 1, polyLeft + scanWidth)
            var leftFound  = polyLeft

            var bestLDist = Double.infinity
            for x in scanLStart..<scanLEnd {
                if isGutter(x, y) && !isGutter(x + 1, y) {
                    let dist = abs(Double(x + 1) - Double(polyLeft))
                    if dist < bestLDist {
                        bestLDist = dist
                        leftFound = x + 1
                    }
                }
            }
            rowLeftEdge[y] = leftFound

            // --- Right edge: find transition from artwork (false) to gutter (true) ---
            let scanRStart = max(0, polyRight - scanWidth)
            let scanREnd   = min(W - 1, polyRight + scanWidth)
            var rightFound = polyRight

            var bestRDist = Double.infinity
            for x in scanRStart..<scanREnd {
                if !isGutter(x, y) && isGutter(x + 1, y) {
                    let dist = abs(Double(x) - Double(polyRight))
                    if dist < bestRDist {
                        bestRDist = dist
                        rightFound = x
                    }
                }
            }
            rowRightEdge[y] = rightFound
        }

        // ── 5. Per-column scan: find top and bottom artwork edges ──────────────

        func topBot(col x: Int) -> (top: Int, bot: Int) {
            // Top: find transition from gutter (true) to artwork (false)
            let scanTStart = max(0, topY - scanHeight)
            let scanTEnd   = min(H - 1, topY + scanHeight)
            var topFound   = topY

            var bestTDist = Double.infinity
            for y in scanTStart..<scanTEnd {
                if isGutter(x, y) && !isGutter(x, y + 1) {
                    let dist = abs(Double(y + 1) - Double(topY))
                    if dist < bestTDist {
                        bestTDist = dist
                        topFound = y + 1
                    }
                }
            }

            // Bottom: find transition from artwork (false) to gutter (true)
            let scanBStart = max(0, botY - scanHeight)
            let scanBEnd   = min(H - 1, botY + scanHeight)
            var botFound   = botY

            var bestBDist = Double.infinity
            for y in scanBStart..<scanBEnd {
                if !isGutter(x, y) && isGutter(x, y + 1) {
                    let dist = abs(Double(y) - Double(botY))
                    if dist < bestBDist {
                        bestBDist = dist
                        botFound = y
                    }
                }
            }

            return (topFound, botFound)
        }

        // Sample top/bottom from a band of columns in the center of the panel
        let midCol   = (Int(tl.x) + Int(tr.x)) / 2
        let colBand  = max(2, (Int(tr.x) - Int(tl.x)) / 6)
        let colRange = max(0, midCol - colBand)...min(W - 1, midCol + colBand)

        var topEdges: [Int] = [], botEdges: [Int] = []
        for x in colRange {
            let (t, b) = topBot(col: x)
            topEdges.append(t); botEdges.append(b)
        }

        let finalTop = topEdges.min() ?? topY
        let finalBot = botEdges.max() ?? botY

        // ── 6. Derive 4 corners from per-row edge arrays ──────────────────────
        // Average top 12.5% of rows for TL/TR, bottom 12.5% for BL/BR
        let rowCount = botY - topY + 1
        let band     = max(1, rowCount / 8)

        func avgLeft(_ rows: any Sequence<Int>) -> Int {
            let vals = rows.filter { $0 >= 0 && $0 < H && rowLeftEdge[$0] >= 0 }.map { rowLeftEdge[$0] }
            return vals.isEmpty ? Int(tl.x) : vals.reduce(0, +) / vals.count
        }
        func avgRight(_ rows: any Sequence<Int>) -> Int {
            let vals = rows.filter { $0 >= 0 && $0 < H && rowRightEdge[$0] >= 0 }.map { rowRightEdge[$0] }
            return vals.isEmpty ? Int(tr.x) : vals.reduce(0, +) / vals.count
        }

        let topRows = (topY...(topY + band))
        let botRows = ((botY - band)...botY)

        let tlPx = avgLeft(topRows);   let trPx = avgRight(topRows)
        let blPx = avgLeft(botRows);   let brPx = avgRight(botRows)

        // ── 7. Normalize to [0,1] ─────────────────────────────────────────────
        func nx(_ v: Int) -> Double { max(0, min(1, Double(v) / Double(W))) }
        func ny(_ v: Int) -> Double { max(0, min(1, Double(v) / Double(H))) }

        return [
            CGPoint(x: nx(tlPx), y: ny(finalTop)),  // TL
            CGPoint(x: nx(trPx), y: ny(finalTop)),  // TR
            CGPoint(x: nx(brPx), y: ny(finalBot)),  // BR
            CGPoint(x: nx(blPx), y: ny(finalBot))   // BL
        ]
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
