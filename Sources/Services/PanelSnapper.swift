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
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue  // Y=0 at top
        ) else { return points }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: W, height: H))

        // ── 1. Detect gutter color from outer page edges ───────────────────────
        let bg = detectGutterColor(raw: raw, W: W, H: H, bpr: bpr, bpp: bpp)
        let tol = 40.0

        func isGutter(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < W, y >= 0, y < H else { return true }
            let o = y * bpr + x * bpp
            return abs(Double(raw[o])   - bg.r) < tol
                && abs(Double(raw[o+1]) - bg.g) < tol
                && abs(Double(raw[o+2]) - bg.b) < tol
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

        // ── 4. Per-row scan: find left and right artwork edges ─────────────────
        // For each row we scan a small window that starts OUTSIDE the polygon
        // boundary (in the gutter) and moves INWARD until hitting artwork.
        let bufPx = max(4, Int(Double(W) * 0.04))  // 4% of image width as gutter buffer

        var rowLeftEdge  = [Int](repeating: -1, count: H)
        var rowRightEdge = [Int](repeating: -1, count: H)

        for y in topY...botY {
            let polyLeft  = lerpX(y, from: tl, to: bl)
            let polyRight = lerpX(y, from: tr, to: br)

            // --- Left edge: scan right-ward from outside the polygon ---
            let scanLStart = max(0, polyLeft - bufPx)
            let scanLEnd   = min(W - 1, polyLeft + bufPx)
            var leftFound  = polyLeft  // fallback: use initial polygon estimate

            for x in scanLStart...scanLEnd {
                if !isGutter(x, y) {
                    leftFound = x
                    break
                }
            }
            rowLeftEdge[y] = leftFound

            // --- Right edge: scan left-ward from outside the polygon ---
            let scanRStart = min(W - 1, polyRight + bufPx)
            let scanREnd   = max(0, polyRight - bufPx)
            var rightFound = polyRight  // fallback

            for x in stride(from: scanRStart, through: scanREnd, by: -1) {
                if !isGutter(x, y) {
                    rightFound = x
                    break
                }
            }
            rowRightEdge[y] = rightFound
        }

        // ── 5. Per-column scan: find top and bottom artwork edges ──────────────
        let leftY  = Int(min(tl.x, bl.x))   // leftmost column to scan
        let rightY = Int(max(tr.x, br.x))   // rightmost column to scan

        func topBot(col x: Int) -> (top: Int, bot: Int) {
            // Top: scan down from outside
            let scanTStart = max(0, topY - bufPx)
            let scanTEnd   = min(H - 1, topY + bufPx)
            var topFound   = topY
            for y in scanTStart...scanTEnd {
                if !isGutter(x, y) { topFound = y; break }
            }
            // Bottom: scan up from outside
            let scanBStart = min(H - 1, botY + bufPx)
            let scanBEnd   = max(0, botY - bufPx)
            var botFound   = botY
            for y in stride(from: scanBStart, through: scanBEnd, by: -1) {
                if !isGutter(x, y) { botFound = y; break }
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

    // MARK: - Gutter Color Detection

    private static func detectGutterColor(
        raw: [UInt8], W: Int, H: Int, bpr: Int, bpp: Int
    ) -> (r: Double, g: Double, b: Double) {
        var rs: [Double] = [], gs: [Double] = [], bs: [Double] = []

        func sample(_ x: Int, _ y: Int) {
            guard x >= 0, x < W, y >= 0, y < H else { return }
            let o = y * bpr + x * bpp
            guard o + 2 < raw.count else { return }
            rs.append(Double(raw[o])); gs.append(Double(raw[o+1])); bs.append(Double(raw[o+2]))
        }

        let xStep = max(1, W / 60), yStep = max(1, H / 60)
        for x in stride(from: 0, to: W, by: xStep) {
            for d in 0...4 { sample(x, d); sample(x, H-1-d) }
        }
        for y in stride(from: 0, to: H, by: yStep) {
            for d in 0...4 { sample(d, y); sample(W-1-d, y) }
        }

        guard !rs.isEmpty else { return (240, 240, 240) }
        rs.sort(); gs.sort(); bs.sort()
        let idx = min(rs.count - 1, (rs.count * 3) / 4)   // 75th percentile
        return (rs[idx], gs[idx], bs[idx])
    }
}
