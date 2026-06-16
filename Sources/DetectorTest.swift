import Foundation
import CoreGraphics
import AppKit

func runDetectorTest() async {
    print("--- STARTING DETECTOR VERIFICATION TEST ---")
    
    let fm = FileManager.default
    let paths = [
        "/Users/aditivignesh/Desktop/GitHub/panel-detection/test_page.png",
        "/Users/aditivignesh/Desktop/GitHub/Comic-Paneling/Sources/Resources/SampleComics/antigravity/page1.png",
        "/Users/aditivignesh/Desktop/GitHub/Comic-Paneling/Sources/Resources/SampleComics/cyberpunk/page1.png"
    ]
    
    for path in paths {
        print("\nTesting image: \(path)")
        guard fm.fileExists(atPath: path) else {
            print("Error: File does not exist at \(path)")
            continue
        }
        guard let image = NSImage(contentsOfFile: path),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("Error: Could not load image as CGImage")
            continue
        }
        
        // Test XY-Cut
        let xyCutRects = await PanelDetector.detectPanels(in: cgImage, direction: .leftToRight, mode: .xycut)
        print("XY-Cut Panels (\(xyCutRects.count) found):")
        for (i, r) in xyCutRects.enumerated() {
            print(String(format: "  Panel %d: x=%.3f, y=%.3f, w=%.3f, h=%.3f", i + 1, r.origin.x, r.origin.y, r.width, r.height))
        }
        
        // Test Contour
        let contourRects = await PanelDetector.detectPanels(in: cgImage, direction: .leftToRight, mode: .contour)
        print("Contour Panels (\(contourRects.count) found):")
        for (i, r) in contourRects.enumerated() {
            print(String(format: "  Panel %d: x=%.3f, y=%.3f, w=%.3f, h=%.3f", i + 1, r.origin.x, r.origin.y, r.width, r.height))
        }
    }
    
    print("\n--- DETECTOR VERIFICATION TEST COMPLETE ---")
}
