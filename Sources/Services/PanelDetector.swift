import Foundation
import CoreGraphics
@preconcurrency import Vision

public class PanelDetector {
    
    /// Detects panels on a given CGImage.
    /// Runs on a background thread and returns detected rects in normalized SwiftUI coordinates (origin top-left, range 0..1).
    public static func detectPanels(in cgImage: CGImage, direction: ReadingDirection = .leftToRight) async -> [CGRect] {
        return await withCheckedContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                guard error == nil else {
                    print("Vision rectangle detection error: \(error!)")
                    // Fallback: Return single panel covering the whole page
                    continuation.resume(returning: [CGRect(x: 0, y: 0, width: 1, height: 1)])
                    return
                }
                
                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: [CGRect(x: 0, y: 0, width: 1, height: 1)])
                    return
                }
                
                if observations.isEmpty {
                    // No panels found, return a single full-page panel as fallback
                    continuation.resume(returning: [CGRect(x: 0, y: 0, width: 1, height: 1)])
                    return
                }
                
                // Convert coordinates from Vision (bottom-left) to SwiftUI (top-left)
                var rects = observations.map { obs -> CGRect in
                    let box = obs.boundingBox
                    return CGRect(
                        x: box.origin.x,
                        y: 1.0 - box.origin.y - box.size.height,
                        width: box.size.width,
                        height: box.size.height
                    )
                }
                
                // Filter out tiny rectangles (less than 2% of page area) or giant rectangles that cover the whole page
                // but only if there are other panel-sized rects.
                let filtered = rects.filter { rect in
                    let area = rect.width * rect.height
                    return area > 0.02 && area < 0.98
                }
                
                if !filtered.isEmpty {
                    rects = filtered
                }
                
                // Sort rects according to reading order
                let sortedRects = sortRects(rects, direction: direction)
                continuation.resume(returning: sortedRects)
            }
            
            // Customize request detection parameters
            request.minimumConfidence = 0.4
            request.minimumSize = 0.08  // Minimum height/width relative to image
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
    
    /// Sorts rectangles in typical comic reading order:
    /// - For LeftToRight: Top-to-bottom rows, left-to-right columns within each row.
    /// - For RightToLeft (Manga): Top-to-bottom rows, right-to-left columns within each row.
    public static func sortRects(_ rects: [CGRect], direction: ReadingDirection) -> [CGRect] {
        guard rects.count > 1 else { return rects }
        
        // Dynamic row grouping: panels are in the same row if they overlap vertically by a threshold.
        // A standard threshold is 15% of the average height of panels.
        let avgHeight = rects.reduce(0.0) { $0 + $1.height } / CGFloat(rects.count)
        let rowThreshold = max(0.05, avgHeight * 0.4) // At least 5% of page height, or 40% of average panel height
        
        var sorted = rects
        
        // First sort top-to-bottom by Y coordinate
        sorted.sort { $0.origin.y < $1.origin.y }
        
        // Group into rows
        var rows: [[CGRect]] = []
        var currentRow: [CGRect] = []
        
        for rect in sorted {
            if currentRow.isEmpty {
                currentRow.append(rect)
            } else {
                // Check if this rect's top overlaps with the current row's average Y center
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
        
        // Sort each row horizontally
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
