import Foundation
import CoreGraphics
@preconcurrency import Vision

public class PanelDetector {
    
    public static func detectPanels(in cgImage: CGImage, direction: ReadingDirection = .leftToRight) async -> [CGRect] {
        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                guard error == nil else {
                    print("Vision rectangle detection error: \(error!)")
                    continuation.resume(returning: [CGRect(x: 0, y: 0, width: 1, height: 1)])
                    return
                }
                
                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: [CGRect(x: 0, y: 0, width: 1, height: 1)])
                    return
                }
                
                if observations.isEmpty {
                    continuation.resume(returning: [CGRect(x: 0, y: 0, width: 1, height: 1)])
                    return
                }
                
                var rects = observations.map { obs -> CGRect in
                    let box = obs.boundingBox
                    return CGRect(
                        x: box.origin.x,
                        y: 1.0 - box.origin.y - box.size.height,
                        width: box.size.width,
                        height: box.size.height
                    )
                }
                
                let filtered = rects.filter { rect in
                    let area = rect.width * rect.height
                    return area > 0.02 && area < 0.98
                }
                
                if !filtered.isEmpty {
                    rects = filtered
                }
                
                let sortedRects = sortRects(rects, direction: direction)
                continuation.resume(returning: sortedRects)
            }
            
            request.minimumConfidence = 0.4
            request.minimumSize = 0.08
            request.minimumAspectRatio = 0.1
            request.maximumAspectRatio = 10.0
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            
            do {
                try handler.perform([request])
            } catch {
                print("Failed to perform Vision request: \(error)")
                continuation.resume(returning: [CGRect(x: 0, y: 0, width: 1, height: 1)])
            }
        }
    }
    
    public static func sortRects(_ rects: [CGRect], direction: ReadingDirection) -> [CGRect] {
        guard rects.count > 1 else { return rects }
        
        let avgHeight = rects.reduce(0.0) { $0 + $1.height } / CGFloat(rects.count)
        let rowThreshold = max(0.05, avgHeight * 0.4)
        
        var sorted = rects
        sorted.sort { $0.origin.y < $1.origin.y }
        
        var rows: [[CGRect]] = []
        var currentRow: [CGRect] = []
        
        for rect in sorted {
            if currentRow.isEmpty {
                currentRow.append(rect)
            } else {
                let rowAvgY = currentRow.reduce(0.0) { $0 + $1.origin.y } / CGFloat(currentRow.count)
                if abs(rect.origin.y - rowAvgY) < rowThreshold {
                    currentRow.append(rect)
                } else {
                    rows.append(currentRow)
                    currentRow = [rect]
                }
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        
        var finalSorted: [CGRect] = []
        for row in rows {
            let sortedRow = row.sorted { r1, r2 in
                if direction == .leftToRight {
                    return r1.origin.x < r2.origin.x
                } else {
                    return r1.origin.x > r2.origin.x
                }
            }
            finalSorted.append(contentsOf: sortedRow)
        }
        
        return finalSorted
    }
}
