package com.paneling.services

import com.paneling.models.PointF

object PanelSnapper {

    fun snapPoints(
        points: List<PointF>,
        raw: ByteArray,
        W: Int,
        H: Int
    ): List<PointF> {
        if (points.size != 4) return points
        if (W <= 4 || H <= 4) return points

        val bpp = 4
        val bpr = bpp * W

        // 1. Determine if background is dark or light, and define gutter test
        val isDarkBg = isPageBackgroundDark(raw, W, H, bpr, bpp)

        fun isGutter(x: Int, y: Int): Boolean {
            if (x < 0 || x >= W || y < 0 || y >= H) return true
            val o = y * bpr + x * bpp
            if (o + 2 >= raw.size) return true
            val r = (raw[o].toInt() and 0xFF).toDouble()
            val g = (raw[o + 1].toInt() and 0xFF).toDouble()
            val b = (raw[o + 2].toInt() and 0xFF).toDouble()

            return if (isDarkBg) {
                val tol = 50.0
                r < tol && g < tol && b < tol
            } else {
                val threshold = 205.0
                r > threshold && g > threshold && b > threshold
            }
        }

        // 2. Polygon corners in pixel space
        // Input order: [TL, TR, BR, BL]
        val tl = PointF(points[0].x * W, points[0].y * H)
        val tr = PointF(points[1].x * W, points[1].y * H)
        val br = PointF(points[2].x * W, points[2].y * H)
        val bl = PointF(points[3].x * W, points[3].y * H)

        val topY = minOf(tl.y, tr.y).toInt()
        val botY = maxOf(bl.y, br.y).toInt()
        if (topY >= botY) return points

        // 3. Linear interpolation along polygon left/right edges
        // Left edge: TL->BL   Right edge: TR->BR
        fun lerpX(y: Int, p0: PointF, p1: PointF): Int {
            if (p1.y <= p0.y) return p0.x.toInt()
            val t = (y.toDouble() - p0.y) / (p1.y - p0.y)
            return (p0.x + t * (p1.x - p0.x)).toInt()
        }

        // 4. Per-row scan: find left and right artwork edges using transition-based matching
        val scanWidth = maxOf(15, (W * 0.02).toInt())
        val scanHeight = maxOf(15, (H * 0.02).toInt())

        val rowLeftEdge = IntArray(H) { -1 }
        val rowRightEdge = IntArray(H) { -1 }

        for (y in topY..botY) {
            if (y < 0 || y >= H) continue
            val polyLeft = lerpX(y, tl, bl)
            val polyRight = lerpX(y, tr, br)

            // --- Left edge: find transition from gutter (true) to artwork (false) ---
            val scanLStart = maxOf(0, polyLeft - scanWidth)
            val scanLEnd = minOf(W - 1, polyLeft + scanWidth)
            var leftFound = polyLeft

            var bestLDist = Double.POSITIVE_INFINITY
            for (x in scanLStart until scanLEnd) {
                if (isGutter(x, y) && !isGutter(x + 1, y)) {
                    val dist = Math.abs((x + 1).toDouble() - polyLeft)
                    if (dist < bestLDist) {
                        bestLDist = dist
                        leftFound = x + 1
                    }
                }
            }
            rowLeftEdge[y] = leftFound

            // --- Right edge: find transition from artwork (false) to gutter (true) ---
            val scanRStart = maxOf(0, polyRight - scanWidth)
            val scanREnd = minOf(W - 1, polyRight + scanWidth)
            var rightFound = polyRight

            var bestRDist = Double.POSITIVE_INFINITY
            for (x in scanRStart until scanREnd) {
                if (!isGutter(x, y) && isGutter(x + 1, y)) {
                    val dist = Math.abs(x.toDouble() - polyRight)
                    if (dist < bestRDist) {
                        bestRDist = dist
                        rightFound = x
                    }
                }
            }
            rowRightEdge[y] = rightFound
        }

        // 5. Per-column scan: find top and bottom artwork edges
        fun topBot(x: Int): Pair<Int, Int> {
            // Top: find transition from gutter (true) to artwork (false)
            val scanTStart = maxOf(0, topY - scanHeight)
            val scanTEnd = minOf(H - 1, topY + scanHeight)
            var topFound = topY

            var bestTDist = Double.POSITIVE_INFINITY
            for (y in scanTStart until scanTEnd) {
                if (isGutter(x, y) && !isGutter(x, y + 1)) {
                    val dist = Math.abs((y + 1).toDouble() - topY)
                    if (dist < bestTDist) {
                        bestTDist = dist
                        topFound = y + 1
                    }
                }
            }

            // Bottom: find transition from artwork (false) to gutter (true)
            val scanBStart = maxOf(0, botY - scanHeight)
            val scanBEnd = minOf(H - 1, botY + scanHeight)
            var botFound = botY

            var bestBDist = Double.POSITIVE_INFINITY
            for (y in scanBStart until scanBEnd) {
                if (!isGutter(x, y) && isGutter(x, y + 1)) {
                    val dist = Math.abs(y.toDouble() - botY)
                    if (dist < bestBDist) {
                        bestBDist = dist
                        botFound = y
                    }
                }
            }

            return Pair(topFound, botFound)
        }

        // Sample top/bottom from a band of columns in the center of the panel
        val midCol = (tl.x.toInt() + tr.x.toInt()) / 2
        val colBand = maxOf(2, (tr.x.toInt() - tl.x.toInt()) / 6)
        val colRange = maxOf(0, midCol - colBand)..minOf(W - 1, midCol + colBand)

        val topEdges = mutableListOf<Int>()
        val botEdges = mutableListOf<Int>()
        for (x in colRange) {
            val (t, b) = topBot(x)
            topEdges.add(t)
            botEdges.add(b)
        }

        val finalTop = topEdges.minOrNull() ?: topY
        val finalBot = botEdges.maxOrNull() ?: botY

        // 6. Derive 4 corners from per-row edge arrays
        val rowCount = botY - topY + 1
        val band = maxOf(1, rowCount / 8)

        fun avgLeft(rows: Iterable<Int>): Int {
            val vals = rows.filter { it in 0 until H && rowLeftEdge[it] >= 0 }.map { rowLeftEdge[it] }
            return if (vals.isEmpty()) tl.x.toInt() else vals.sum() / vals.size
        }
        fun avgRight(rows: Iterable<Int>): Int {
            val vals = rows.filter { it in 0 until H && rowRightEdge[it] >= 0 }.map { rowRightEdge[it] }
            return if (vals.isEmpty()) tr.x.toInt() else vals.sum() / vals.size
        }

        val topRows = topY..(topY + band)
        val botRows = (botY - band)..botY

        val tlPx = avgLeft(topRows)
        val trPx = avgRight(topRows)
        val blPx = avgLeft(botRows)
        val brPx = avgRight(botRows)

        // 7. Normalize to [0,1]
        fun nx(v: Int): Double {
            return maxOf(0.0, minOf(1.0, v.toDouble() / W))
        }
        fun ny(v: Int): Double {
            return maxOf(0.0, minOf(1.0, v.toDouble() / H))
        }

        return listOf(
            PointF(nx(tlPx), ny(finalTop)), // TL
            PointF(nx(trPx), ny(finalTop)), // TR
            PointF(nx(brPx), ny(finalBot)), // BR
            PointF(nx(blPx), ny(finalBot))  // BL
        )
    }

    private fun isPageBackgroundDark(raw: ByteArray, W: Int, H: Int, bpr: Int, bpp: Int): Boolean {
        val brightnesses = mutableListOf<Double>()

        fun sample(x: Int, y: Int) {
            if (x in 0 until W && y in 0 until H) {
                val o = y * bpr + x * bpp
                if (o + 2 < raw.size) {
                    val r = (raw[o].toInt() and 0xFF).toDouble()
                    val g = (raw[o + 1].toInt() and 0xFF).toDouble()
                    val b = (raw[o + 2].toInt() and 0xFF).toDouble()
                    brightnesses.add((r + g + b) / 3.0)
                }
            }
        }

        val xStep = maxOf(1, W / 60)
        val yStep = maxOf(1, H / 60)
        for (x in 0 until W step xStep) {
            for (d in 0..4) {
                sample(x, d)
                sample(x, H - 1 - d)
            }
        }
        for (y in 0 until H step yStep) {
            for (d in 0..4) {
                sample(d, y)
                sample(W - 1 - d, y)
            }
        }

        if (brightnesses.isEmpty()) return false
        brightnesses.sort()
        return brightnesses[brightnesses.size / 2] < 80.0
    }
}
