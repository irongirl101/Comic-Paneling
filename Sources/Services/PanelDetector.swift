import Foundation
import CoreGraphics
import Vision

public class PanelDetector {

    public enum DetectionMode {
        case contour
        case xycut
    }

    /// Public interface for panel detection. Defaults to the robust xycut mode.
    public static func detectPanels(
        in cgImage: CGImage,
        direction: ReadingDirection = .leftToRight,
        mode: DetectionMode = .xycut
    ) async -> [CGRect] {
        switch mode {
        case .contour:
            return await detectPanelsContour(in: cgImage, direction: direction)
        case .xycut:
            return detectPanelsXYCut(in: cgImage, direction: direction)
        }
    }

    // MARK: - XY-Cut Projection Splitting Method

    private static func detectPanelsXYCut(
        in cgImage: CGImage,
        direction: ReadingDirection,
        xycutThreshold: Double = 0.84, // Equivalent to 215/255
        minAreaPct: Double = 0.015
    ) -> [CGRect] {
        
        let W = cgImage.width
        let H = cgImage.height
        guard W > 4, H > 4 else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }

        let bpp = 4
        let bpr = bpp * W
        var raw = [UInt8](repeating: 0, count: H * bpr)
        guard let ctx = CGContext(
            data: &raw, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        
        // Draw top-down into buffer
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: W, height: H))

        // Determine edge background color
        let bg = detectMedianEdgeColor(raw: raw, W: W, H: H, bpr: bpr, bpp: bpp)

        func isGutter(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < W, y >= 0, y < H else { return true }
            let o = y * bpr + x * bpp
            let r = Double(raw[o])
            let g = Double(raw[o+1])
            let b = Double(raw[o+2])
            
            let gray = 0.299 * r + 0.587 * g + 0.114 * b
            if bg.isDark {
                return gray < 40.0
            } else {
                return gray > 240.0
            }
        }

        // 1. Initial border cropping to find the page contents boundary
        var yMin = 0, yMax = H - 1
        var xMin = 0, xMax = W - 1
        
        // Find yMin
        for y in 0..<H {
            var rowSum = 0
            for x in 0..<W {
                if isGutter(x, y) { rowSum += 1 }
            }
            if Double(rowSum) / Double(W) < 0.99 {
                yMin = y
                break
            }
        }
        
        // Find yMax
        for y in stride(from: H - 1, through: 0, by: -1) {
            var rowSum = 0
            for x in 0..<W {
                if isGutter(x, y) { rowSum += 1 }
            }
            if Double(rowSum) / Double(W) < 0.99 {
                yMax = y
                break
            }
        }
        
        // Find xMin
        for x in 0..<W {
            var colSum = 0
            for y in 0..<H {
                if isGutter(x, y) { colSum += 1 }
            }
            if Double(colSum) / Double(H) < 0.99 {
                xMin = x
                break
            }
        }
        
        // Find xMax
        for x in stride(from: W - 1, through: 0, by: -1) {
            var colSum = 0
            for y in 0..<H {
                if isGutter(x, y) { colSum += 1 }
            }
            if Double(colSum) / Double(H) < 0.99 {
                xMax = x
                break
            }
        }
        
        guard xMax > xMin, yMax > yMin else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        
        // 2. Recursive Split helper structures
        struct SubRect {
            var x1: Int
            var y1: Int
            var x2: Int
            var y2: Int
            
            var width: Int { x2 - x1 }
            var height: Int { y2 - y1 }
        }
        
        func findSplits(in rect: SubRect, axis: Int) -> [(Int, Int)] {
            if rect.height <= 10 || rect.width <= 10 { return [] }
            
            var splits: [(Int, Int)] = []
            var inGutter = false
            var startIdx = 0
            
            if axis == 0 { // Horizontal split check (rows)
                for y in 0..<rect.height {
                    let globalY = rect.y1 + y
                    var gutterCount = 0
                    for x in 0..<rect.width {
                        let globalX = rect.x1 + x
                        if isGutter(globalX, globalY) {
                            gutterCount += 1
                        }
                    }
                    let rowMean = Double(gutterCount) / Double(rect.width)
                    let isGutterRow = rowMean > xycutThreshold
                    
                    if isGutterRow && !inGutter {
                        inGutter = true
                        startIdx = y
                    } else if !isGutterRow && inGutter {
                        inGutter = false
                        let endIdx = y
                        if endIdx - startIdx > 4 {
                            splits.append((rect.y1 + startIdx, rect.y1 + endIdx))
                        }
                    }
                }
            } else { // Vertical split check (columns)
                for x in 0..<rect.width {
                    let globalX = rect.x1 + x
                    var gutterCount = 0
                    for y in 0..<rect.height {
                        let globalY = rect.y1 + y
                        if isGutter(globalX, globalY) {
                            gutterCount += 1
                        }
                    }
                    let colMean = Double(gutterCount) / Double(rect.height)
                    let isGutterCol = colMean > xycutThreshold
                    
                    if isGutterCol && !inGutter {
                        inGutter = true
                        startIdx = x
                    } else if !isGutterCol && inGutter {
                        inGutter = false
                        let endIdx = x
                        if endIdx - startIdx > 4 {
                            splits.append((rect.x1 + startIdx, rect.x1 + endIdx))
                        }
                    }
                }
            }
            return splits
        }
        
        func recursiveSplit(rect: SubRect) -> [SubRect] {
            // A. Try Horizontal splits (split page into rows)
            let hSplits = findSplits(in: rect, axis: 0).filter { 
                $0.0 - rect.y1 > 20 && rect.y2 - $0.1 > 20 
            }
            
            if !hSplits.isEmpty {
                var yCoords = [rect.y1]
                for split in hSplits {
                    yCoords.append((split.0 + split.1) / 2)
                }
                yCoords.append(rect.y2)
                
                var results: [SubRect] = []
                for i in 0..<(yCoords.count - 1) {
                    let subRect = SubRect(x1: rect.x1, y1: yCoords[i], x2: rect.x2, y2: yCoords[i+1])
                    results.append(contentsOf: recursiveSplit(rect: subRect))
                }
                return results
            }
            
            // B. Try Vertical splits (split row into columns)
            let vSplits = findSplits(in: rect, axis: 1).filter { 
                $0.0 - rect.x1 > 20 && rect.x2 - $0.1 > 20 
            }
            
            if !vSplits.isEmpty {
                var xCoords = [rect.x1]
                for split in vSplits {
                    xCoords.append((split.0 + split.1) / 2)
                }
                xCoords.append(rect.x2)
                
                var results: [SubRect] = []
                for i in 0..<(xCoords.count - 1) {
                    let subRect = SubRect(x1: xCoords[i], y1: rect.y1, x2: xCoords[i+1], y2: rect.y2)
                    results.append(contentsOf: recursiveSplit(rect: subRect))
                }
                return results
            }
            
            // C. Base case: tighten margins to fit black border tightly
            var tightenedX1 = rect.x1, tightenedY1 = rect.y1
            var tightenedX2 = rect.x2, tightenedY2 = rect.y2
            
            var foundContent = false
            outerLoop: for y in 0..<rect.height {
                let globalY = rect.y1 + y
                for x in 0..<rect.width {
                    let globalX = rect.x1 + x
                    if !isGutter(globalX, globalY) {
                        tightenedY1 = globalY
                        foundContent = true
                        break outerLoop
                    }
                }
            }
            
            if foundContent {
                foundContent = false
                outerLoop: for y in stride(from: rect.height - 1, through: 0, by: -1) {
                    let globalY = rect.y1 + y
                    for x in 0..<rect.width {
                        let globalX = rect.x1 + x
                        if !isGutter(globalX, globalY) {
                            tightenedY2 = globalY
                            foundContent = true
                            break outerLoop
                        }
                    }
                }
                
                foundContent = false
                outerLoop: for x in 0..<rect.width {
                    let globalX = rect.x1 + x
                    for y in 0..<rect.height {
                        let globalY = rect.y1 + y
                        if !isGutter(globalX, globalY) {
                            tightenedX1 = globalX
                            foundContent = true
                            break outerLoop
                        }
                    }
                }
                
                foundContent = false
                outerLoop: for x in stride(from: rect.width - 1, through: 0, by: -1) {
                    let globalX = rect.x1 + x
                    for y in 0..<rect.height {
                        let globalY = rect.y1 + y
                        if !isGutter(globalX, globalY) {
                            tightenedX2 = globalX
                            foundContent = true
                            break outerLoop
                        }
                    }
                }
            }
            
            return [SubRect(x1: tightenedX1, y1: tightenedY1, x2: tightenedX2, y2: tightenedY2)]
        }
        
        let initialRect = SubRect(x1: xMin, y1: yMin, x2: xMax, y2: yMax)
        let splitRects = recursiveSplit(rect: initialRect)
        
        // Filter by area constraints
        let totalArea = Double(W * H)
        let minArea = totalArea * minAreaPct
        
        let filteredRects = splitRects.filter { rect in
            let area = Double(rect.width * rect.height)
            guard area >= minArea else { return false }
            let aspect = Double(rect.width) / Double(rect.height)
            return aspect >= 0.1 && aspect <= 10.0
        }
        
        guard !filteredRects.isEmpty else {
            return [CGRect(x: 0, y: 0, width: 1, height: 1)]
        }
        
        let cgRects = filteredRects.map { rect in
            CGRect(
                x: Double(rect.x1) / Double(W),
                y: Double(rect.y1) / Double(H),
                width: Double(rect.width) / Double(W),
                height: Double(rect.height) / Double(H)
            )
        }
        
        return sortRects(cgRects, direction: direction)
    }

    // MARK: - Contour-Based Segmentation Method (Original)

    private static func detectPanelsContour(
        in cgImage: CGImage,
        direction: ReadingDirection
    ) async -> [CGRect] {
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
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: W, height: H))

        let bg = detectMedianEdgeColor(raw: raw, W: W, H: H, bpr: bpr, bpp: bpp)

        func isGutter(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, x < W, y >= 0, y < H else { return true }
            let o = y * bpr + x * bpp
            let r = Double(raw[o])
            let g = Double(raw[o+1])
            let b = Double(raw[o+2])
            
            let gray = 0.299 * r + 0.587 * g + 0.114 * b
            if bg.isDark {
                return gray < 40.0
            } else {
                return gray > 240.0
            }
        }

        let scale = min(1.0, 1024.0 / Double(max(W, H)))
        let mW = max(4, Int(Double(W) * scale))
        let mH = max(4, Int(Double(H) * scale))

        var mask = [Bool](repeating: false, count: mW * mH)
        for my in 0..<mH {
            for mx in 0..<mW {
                let px = Int(Double(mx) / scale)
                let py = Int(Double(my) / scale)
                mask[my * mW + mx] = isGutter(px, py)
            }
        }

        var dilatedMask = mask
        for my in 1..<(mH - 1) {
            for mx in 1..<(mW - 1) {
                if mask[my * mW + mx] { continue }
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

        var candidates: [CGRect] = []
        let totalPixels = Double(mW * mH)
        let minArea = totalPixels * 0.025
        let maxArea = totalPixels * 0.95

        for b in regionBounds {
            let w = b.maxX - b.minX + 1
            let h = b.maxY - b.minY + 1
            let area = Double(w * h)
            
            guard area >= minArea, area <= maxArea else { continue }
            
            let aspect = Double(w) / Double(h)
            guard aspect >= 0.1, aspect <= 10.0 else { continue }
            
            let nX = Double(b.minX) / Double(mW)
            let nY = Double(b.minY) / Double(mH)
            let nW = Double(w) / Double(mW)
            let nH = Double(h) / Double(mH)
            candidates.append(CGRect(x: nX, y: nY, width: nW, height: nH))
        }

        var toReject = Set<Int>()
        for i in 0..<candidates.count {
            let rectA = candidates[i]
            let areaA = rectA.width * rectA.height
            
            var childrenIndices: [Int] = []
            for j in 0..<candidates.count {
                if i == j { continue }
                let rectB = candidates[j]
                
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
                if areaA > 0.60 && childrenIndices.count >= 2 {
                    toReject.insert(i)
                } else {
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

        var finalRects: [CGRect] = []
        let sortedCandidates = filtered.sorted { ($0.width * $0.height) < ($1.width * $1.height) }
        
        for rect in sortedCandidates {
            var shouldKeep = true
            for existing in finalRects {
                let intersection = rect.intersection(existing)
                if !intersection.isNull {
                    let interArea = intersection.width * intersection.height
                    let minArea = min(rect.width * rect.height, existing.width * existing.height)
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

        return sortRects(finalRects, direction: direction)
    }

    // MARK: - Shared Helpers

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
        
        return (medianR, medianG, medianB, brightness < 90.0)
    }
}
