package com.paneling.services

import com.paneling.models.ReadingDirection
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PanelDetectorTest {

    @Test
    fun testDetectPanelsXYCut() {
        val W = 100
        val H = 100
        val bpp = 4
        val bpr = W * bpp
        val raw = ByteArray(H * bpr)

        // 1. Fill entire image with white background (R=255, G=255, B=255, A=255)
        for (i in raw.indices step 4) {
            raw[i] = 255.toByte()     // R
            raw[i + 1] = 255.toByte() // G
            raw[i + 2] = 255.toByte() // B
            raw[i + 3] = 255.toByte() // A
        }

        // 2. Draw 4 dark panels (R=100, G=100, B=100, A=255)
        fun drawPanel(xStart: Int, xEnd: Int, yStart: Int, yEnd: Int) {
            for (y in yStart..yEnd) {
                for (x in xStart..xEnd) {
                    val o = y * bpr + x * bpp
                    raw[o] = 100.toByte()
                    raw[o + 1] = 100.toByte()
                    raw[o + 2] = 100.toByte()
                }
            }
        }

        // Draw 4 distinct square panels with gutters in between
        drawPanel(10, 40, 10, 40) // Top-Left
        drawPanel(60, 90, 10, 40) // Top-Right
        drawPanel(10, 40, 60, 90) // Bottom-Left
        drawPanel(60, 90, 60, 90) // Bottom-Right

        // 3. Run Panel Detector using XY-Cut Mode
        val panels = PanelDetector.detectPanels(
            raw = raw,
            width = W,
            height = H,
            bytesPerRow = bpr,
            direction = ReadingDirection.LEFT_TO_RIGHT,
            mode = PanelDetector.DetectionMode.XYCUT
        )

        // Expecting exactly 4 panels detected
        assertEquals(4, panels.size, "Should detect exactly 4 panels")

        // Validate that the detected areas are near the drawn coordinates
        // Normalized coordinate validations:
        // Panel 1: top-left (around x=0.10, y=0.10, w=0.30, h=0.30)
        val p1 = panels[0]
        assertTrue(p1.x in 0.05..0.15)
        assertTrue(p1.y in 0.05..0.15)
        assertTrue(p1.width in 0.25..0.35)
        assertTrue(p1.height in 0.25..0.35)
    }

    @Test
    fun testDetectPanelsContour() {
        val W = 100
        val H = 100
        val bpp = 4
        val bpr = W * bpp
        val raw = ByteArray(H * bpr)

        // Fill background with white
        for (i in raw.indices step 4) {
            raw[i] = 255.toByte()
            raw[i + 1] = 255.toByte()
            raw[i + 2] = 255.toByte()
            raw[i + 3] = 255.toByte()
        }

        // Draw 4 panels
        fun drawPanel(xStart: Int, xEnd: Int, yStart: Int, yEnd: Int) {
            for (y in yStart..yEnd) {
                for (x in xStart..xEnd) {
                    val o = y * bpr + x * bpp
                    raw[o] = 100.toByte()
                    raw[o + 1] = 100.toByte()
                    raw[o + 2] = 100.toByte()
                }
            }
        }

        drawPanel(10, 40, 10, 40)
        drawPanel(60, 90, 10, 40)
        drawPanel(10, 40, 60, 90)
        drawPanel(60, 90, 60, 90)

        // Run Contour Mode
        val panels = PanelDetector.detectPanels(
            raw = raw,
            width = W,
            height = H,
            bytesPerRow = bpr,
            direction = ReadingDirection.LEFT_TO_RIGHT,
            mode = PanelDetector.DetectionMode.CONTOUR
        )

        // Validate we found panels
        assertTrue(panels.isNotEmpty(), "Contour mode should find panels")
    }
}
