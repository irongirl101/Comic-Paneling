package com.paneling.services

import com.paneling.models.RectF
import com.paneling.models.ReadingDirection

object PanelDetector {

    enum class DetectionMode {
        CONTOUR,
        XYCUT
    }

    fun detectPanels(
        raw: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        direction: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT,
        mode: DetectionMode = DetectionMode.XYCUT
    ): List<RectF> {
        return when (mode) {
            DetectionMode.CONTOUR -> detectPanelsContour(raw, width, height, bytesPerRow, direction)
            DetectionMode.XYCUT -> detectPanelsXYCut(raw, width, height, bytesPerRow, direction)
        }
    }

    private fun computeGutterMask(
        raw: ByteArray,
        W: Int,
        H: Int,
        bpr: Int,
        bpp: Int,
        isDark: Boolean
    ): BooleanArray {
        val mask = BooleanArray(W * H)
        for (y in 0 until H) {
            val rowOffset = y * bpr
            val targetOffset = y * W
            for (x in 0 until W) {
                val o = rowOffset + x * bpp
                val r = raw[o].toInt() and 0xFF
                val g = raw[o + 1].toInt() and 0xFF
                val b = raw[o + 2].toInt() and 0xFF
                val gray = (77 * r + 150 * g + 29 * b) shr 8
                mask[targetOffset + x] = if (isDark) gray < 40 else gray > 240
            }
        }
        return mask
    }

    private fun detectPanelsXYCut(
        raw: ByteArray,
        W: Int,
        H: Int,
        bpr: Int,
        direction: ReadingDirection,
        xycutThreshold: Double = 0.84,
        minAreaPct: Double = 0.015
    ): List<RectF> {
        val bpp = 4
        val bg = detectMedianEdgeColor(raw, W, H, bpr, bpp)
        val gutterMask = computeGutterMask(raw, W, H, bpr, bpp, bg.isDark)

        fun isGutter(x: Int, y: Int): Boolean {
            if (x < 0 || x >= W || y < 0 || y >= H) return true
            return gutterMask[y * W + x]
        }

        var yMin = 0
        var yMax = H - 1
        var xMin = 0
        var xMax = W - 1

        for (y in 0 until H) {
            var rowSum = 0
            for (x in 0 until W) {
                if (isGutter(x, y)) rowSum++
            }
            if (rowSum.toDouble() / W < 0.99) {
                yMin = y
                break
            }
        }

        for (y in H - 1 downTo 0) {
            var rowSum = 0
            for (x in 0 until W) {
                if (isGutter(x, y)) rowSum++
            }
            if (rowSum.toDouble() / W < 0.99) {
                yMax = y
                break
            }
        }

        for (x in 0 until W) {
            var colSum = 0
            for (y in 0 until H) {
                if (isGutter(x, y)) colSum++
            }
            if (colSum.toDouble() / H < 0.99) {
                xMin = x
                break
            }
        }

        for (x in W - 1 downTo 0) {
            var colSum = 0
            for (y in 0 until H) {
                if (isGutter(x, y)) colSum++
            }
            if (colSum.toDouble() / H < 0.99) {
                xMax = x
                break
            }
        }

        if (xMax <= xMin || yMax <= yMin) {
            return listOf(RectF(0.0, 0.0, 1.0, 1.0))
        }

        data class SubRect(val x1: Int, val y1: Int, val x2: Int, val y2: Int) {
            val width: Int get() = x2 - x1
            val height: Int get() = y2 - y1
        }

        fun findSplits(rect: SubRect, axis: Int): List<Pair<Int, Int>> {
            if (rect.height <= 10 || rect.width <= 10) return emptyList()

            val splits = mutableListOf<Pair<Int, Int>>()
            var inGutter = false
            var startIdx = 0

            if (axis == 0) {
                for (y in 0 until rect.height) {
                    val globalY = rect.y1 + y
                    var gutterCount = 0
                    for (x in 0 until rect.width) {
                        val globalX = rect.x1 + x
                        if (isGutter(globalX, globalY)) gutterCount++
                    }
                    val rowMean = gutterCount.toDouble() / rect.width
                    val isGutterRow = rowMean > xycutThreshold

                    if (isGutterRow && !inGutter) {
                        inGutter = true
                        startIdx = y
                    } else if (!isGutterRow && inGutter) {
                        inGutter = false
                        val endIdx = y
                        if (endIdx - startIdx > 4) {
                            splits.add(Pair(rect.y1 + startIdx, rect.y1 + endIdx))
                        }
                    }
                }
            } else {
                for (x in 0 until rect.width) {
                    val globalX = rect.x1 + x
                    var gutterCount = 0
                    for (y in 0 until rect.height) {
                        val globalY = rect.y1 + y
                        if (isGutter(globalX, globalY)) gutterCount++
                    }
                    val colMean = gutterCount.toDouble() / rect.height
                    val isGutterCol = colMean > xycutThreshold

                    if (isGutterCol && !inGutter) {
                        inGutter = true
                        startIdx = x
                    } else if (!isGutterCol && inGutter) {
                        inGutter = false
                        val endIdx = x
                        if (endIdx - startIdx > 4) {
                            splits.add(Pair(rect.x1 + startIdx, rect.x1 + endIdx))
                        }
                    }
                }
            }
            return splits
        }

        fun recursiveSplit(rect: SubRect): List<SubRect> {
            val hSplits = findSplits(rect, 0).filter {
                it.first - rect.y1 > 20 && rect.y2 - it.second > 20
            }

            if (hSplits.isNotEmpty()) {
                val yCoords = mutableListOf<Int>()
                yCoords.add(rect.y1)
                for (split in hSplits) {
                    yCoords.add((split.first + split.second) / 2)
                }
                yCoords.add(rect.y2)

                val results = mutableListOf<SubRect>()
                for (i in 0 until yCoords.size - 1) {
                    val subRect = SubRect(rect.x1, yCoords[i], rect.x2, yCoords[i + 1])
                    results.addAll(recursiveSplit(subRect))
                }
                return results
            }

            val vSplits = findSplits(rect, 1).filter {
                it.first - rect.x1 > 20 && rect.x2 - it.second > 20
            }

            if (vSplits.isNotEmpty()) {
                val xCoords = mutableListOf<Int>()
                xCoords.add(rect.x1)
                for (split in vSplits) {
                    xCoords.add((split.first + split.second) / 2)
                }
                xCoords.add(rect.x2)

                val results = mutableListOf<SubRect>()
                for (i in 0 until xCoords.size - 1) {
                    val subRect = SubRect(xCoords[i], rect.y1, xCoords[i + 1], rect.y2)
                    results.addAll(recursiveSplit(subRect))
                }
                return results
            }

            var tightenedX1 = rect.x1
            var tightenedY1 = rect.y1
            var tightenedX2 = rect.x2
            var tightenedY2 = rect.y2

            var foundContent = false
            outerHorizontalMin@ for (y in 0 until rect.height) {
                val globalY = rect.y1 + y
                for (x in 0 until rect.width) {
                    val globalX = rect.x1 + x
                    if (!isGutter(globalX, globalY)) {
                        tightenedY1 = globalY
                        foundContent = true
                        break@outerHorizontalMin
                    }
                }
            }

            if (foundContent) {
                foundContent = false
                outerHorizontalMax@ for (y in rect.height - 1 downTo 0) {
                    val globalY = rect.y1 + y
                    for (x in 0 until rect.width) {
                        val globalX = rect.x1 + x
                        if (!isGutter(globalX, globalY)) {
                            tightenedY2 = globalY
                            foundContent = true
                            break@outerHorizontalMax
                        }
                    }
                }

                foundContent = false
                outerVerticalMin@ for (x in 0 until rect.width) {
                    val globalX = rect.x1 + x
                    for (y in 0 until rect.height) {
                        val globalY = rect.y1 + y
                        if (!isGutter(globalX, globalY)) {
                            tightenedX1 = globalX
                            foundContent = true
                            break@outerVerticalMin
                        }
                    }
                }

                foundContent = false
                outerVerticalMax@ for (x in rect.width - 1 downTo 0) {
                    val globalX = rect.x1 + x
                    for (y in 0 until rect.height) {
                        val globalY = rect.y1 + y
                        if (!isGutter(globalX, globalY)) {
                            tightenedX2 = globalX
                            foundContent = true
                            break@outerVerticalMax
                        }
                    }
                }
            }

            return listOf(SubRect(tightenedX1, tightenedY1, tightenedX2, tightenedY2))
        }

        val initialRect = SubRect(xMin, yMin, xMax, yMax)
        val splitRects = recursiveSplit(initialRect)

        val totalArea = (W * H).toDouble()
        val minArea = totalArea * minAreaPct

        val filteredRects = splitRects.filter { rect ->
            val area = (rect.width * rect.height).toDouble()
            if (area < minArea) return@filter false
            val aspect = rect.width.toDouble() / rect.height
            aspect in 0.1..10.0
        }

        if (filteredRects.isEmpty()) {
            return listOf(RectF(0.0, 0.0, 1.0, 1.0))
        }

        val cgRects = filteredRects.map { rect ->
            RectF(
                x = rect.x1.toDouble() / W,
                y = rect.y1.toDouble() / H,
                width = rect.width.toDouble() / W,
                height = rect.height.toDouble() / H
            )
        }

        return sortRects(cgRects, direction)
    }

    private fun detectPanelsContour(
        raw: ByteArray,
        W: Int,
        H: Int,
        bpr: Int,
        direction: ReadingDirection
    ): List<RectF> {
        val bpp = 4
        val bg = detectMedianEdgeColor(raw, W, H, bpr, bpp)
        val gutterMask = computeGutterMask(raw, W, H, bpr, bpp, bg.isDark)

        val mW = W
        val mH = H
        var mask = gutterMask.clone()

        val dilatedMask = mask.clone()
        for (my in 1 until mH - 1) {
            for (mx in 1 until mW - 1) {
                if (mask[my * mW + mx]) continue
                val neighbors = intArrayOf(
                    (my - 1) * mW + (mx - 1), (my - 1) * mW + mx, (my - 1) * mW + (mx + 1),
                    my * mW + (mx - 1),                           my * mW + (mx + 1),
                    (my + 1) * mW + (mx - 1), (my + 1) * mW + mx, (my + 1) * mW + (mx + 1)
                )
                for (idx in neighbors) {
                    if (mask[idx]) {
                        dilatedMask[my * mW + mx] = true
                        break
                    }
                }
            }
        }
        mask = dilatedMask

        val labels = IntArray(mW * mH) { -1 }

        data class RegionBounds(
            var minX: Int,
            var minY: Int,
            var maxX: Int,
            var maxY: Int,
            var area: Int
        )

        val regionBounds = mutableListOf<RegionBounds>()
        var labelCounter = 0
        
        // Single pre-allocated queue buffer to avoid GC churn inside loop
        val queue = IntArray(mW * mH)

        for (startY in 0 until mH) {
            for (startX in 0 until mW) {
                val startIdx = startY * mW + startX
                if (mask[startIdx] || labels[startIdx] != -1) continue

                val label = labelCounter
                labelCounter++
                regionBounds.add(RegionBounds(startX, startY, startX, startY, 0))

                var queueWrite = 0
                var queueRead = 0

                queue[queueWrite++] = startIdx
                labels[startIdx] = label

                while (queueRead < queueWrite) {
                    val currIdx = queue[queueRead++]
                    val cx = currIdx % mW
                    val cy = currIdx / mW

                    val rBounds = regionBounds[label]
                    rBounds.area++
                    if (cx < rBounds.minX) rBounds.minX = cx
                    if (cx > rBounds.maxX) rBounds.maxX = cx
                    if (cy < rBounds.minY) rBounds.minY = cy
                    if (cy > rBounds.maxY) rBounds.maxY = cy

                    val neighbors = arrayOf(
                        Pair(cx - 1, cy),
                        Pair(cx + 1, cy),
                        Pair(cx, cy - 1),
                        Pair(cx, cy + 1)
                    )
                    for (n in neighbors) {
                        val nx = n.first
                        val ny = n.second
                        if (nx >= 0 && nx < mW && ny >= 0 && ny < mH) {
                            val nIdx = ny * mW + nx
                            if (!mask[nIdx] && labels[nIdx] == -1) {
                                labels[nIdx] = label
                                queue[queueWrite++] = nIdx
                            }
                        }
                    }
                }
            }
        }

        val candidates = mutableListOf<RectF>()
        val totalPixels = (mW * mH).toDouble()
        val minArea = totalPixels * 0.025
        val maxArea = totalPixels * 0.95

        for (b in regionBounds) {
            val w = b.maxX - b.minX + 1
            val h = b.maxY - b.minY + 1
            val area = (w * h).toDouble()

            if (area < minArea || area > maxArea) continue

            val aspect = w.toDouble() / h
            if (aspect < 0.1 || aspect > 10.0) continue

            val nX = b.minX.toDouble() / mW
            val nY = b.minY.toDouble() / mH
            val nW = w.toDouble() / mW
            val nH = h.toDouble() / mH
            candidates.add(RectF(nX, nY, nW, nH))
        }

        val toReject = mutableSetOf<Int>()
        for (i in 0 until candidates.size) {
            val rectA = candidates[i]
            val areaA = rectA.width * rectA.height

            val childrenIndices = mutableListOf<Int>()
            for (j in 0 until candidates.size) {
                if (i == j) continue
                val rectB = candidates[j]

                val isInside = rectB.minX >= rectA.minX - 0.01 &&
                        rectB.maxX <= rectA.maxX + 0.01 &&
                        rectB.minY >= rectA.minY - 0.01 &&
                        rectB.maxY <= rectA.maxY + 0.01

                val isSmaller = (rectB.width * rectB.height) < areaA * 0.9

                if (isInside && isSmaller) {
                    childrenIndices.add(j)
                }
            }

            if (childrenIndices.isNotEmpty()) {
                if (areaA > 0.60 && childrenIndices.size >= 2) {
                    toReject.add(i)
                } else {
                    for (childIdx in childrenIndices) {
                        toReject.add(childIdx)
                    }
                }
            }
        }

        val filtered = mutableListOf<RectF>()
        for (i in 0 until candidates.size) {
            if (!toReject.contains(i)) {
                filtered.add(candidates[i])
            }
        }

        val finalRects = mutableListOf<RectF>()
        val sortedCandidates = filtered.sortedBy { it.width * it.height }

        for (rect in sortedCandidates) {
            var shouldKeep = true
            for (existing in finalRects) {
                val intersection = rect.intersection(existing)
                if (!intersection.isNull) {
                    val interArea = intersection.width * intersection.height
                    val minA = minOf(rect.width * rect.height, existing.width * existing.height)
                    if (interArea / minA > 0.8) {
                        shouldKeep = false
                        break
                    }
                }
            }
            if (shouldKeep) {
                finalRects.add(rect)
            }
        }

        if (finalRects.isEmpty()) {
            return listOf(RectF(0.0, 0.0, 1.0, 1.0))
        }

        return sortRects(finalRects, direction)
    }

    fun sortRects(rects: List<RectF>, direction: ReadingDirection): List<RectF> {
        if (rects.size <= 1) return rects

        val avgHeight = rects.map { it.height }.average()
        val rowThreshold = maxOf(0.04, avgHeight * 0.5)

        val rows = mutableListOf<List<RectF>>()
        var remaining = rects.sortedBy { it.y }

        while (remaining.isNotEmpty()) {
            val pivot = remaining.first()
            remaining = remaining.drop(1)

            val currentRow = mutableListOf<RectF>()
            currentRow.add(pivot)

            val nextRemaining = mutableListOf<RectF>()
            for (rect in remaining) {
                if (Math.abs(rect.midY - pivot.midY) < rowThreshold) {
                    currentRow.add(rect)
                } else {
                    nextRemaining.add(rect)
                }
            }
            remaining = nextRemaining

            currentRow.sortWith(Comparator { a, b ->
                if (direction == ReadingDirection.LEFT_TO_RIGHT) {
                    a.x.compareTo(b.x)
                } else {
                    b.x.compareTo(a.x)
                }
            })

            rows.add(currentRow)
        }

        return rows.flatten()
    }

    private data class MedianColorResult(val r: Double, val g: Double, val b: Double, val isDark: Boolean)

    private fun detectMedianEdgeColor(raw: ByteArray, W: Int, H: Int, bpr: Int, bpp: Int): MedianColorResult {
        val rs = mutableListOf<Double>()
        val gs = mutableListOf<Double>()
        val bs = mutableListOf<Double>()

        val edgeOffsetX = maxOf(5, (W * 0.015).toInt())
        val edgeOffsetY = maxOf(5, (H * 0.015).toInt())

        fun sample(x: Int, y: Int) {
            if (x in 0 until W && y in 0 until H) {
                val o = y * bpr + x * bpp
                if (o + 2 < raw.size) {
                    rs.add((raw[o].toInt() and 0xFF).toDouble())
                    gs.add((raw[o + 1].toInt() and 0xFF).toDouble())
                    bs.add((raw[o + 2].toInt() and 0xFF).toDouble())
                }
            }
        }

        val xStep = maxOf(1, W / 60)
        val yStep = maxOf(1, H / 60)
        for (x in 0 until W step xStep) {
            for (d in 0..4) {
                sample(x, edgeOffsetY + d)
                sample(x, H - 1 - edgeOffsetY - d)
            }
        }
        for (y in 0 until H step yStep) {
            for (d in 0..4) {
                sample(edgeOffsetX + d, y)
                sample(W - 1 - edgeOffsetX - d, y)
            }
        }

        if (rs.isEmpty()) {
            return MedianColorResult(240.0, 240.0, 240.0, false)
        }
        rs.sort()
        gs.sort()
        bs.sort()

        val mid = rs.size / 2
        val medianR = rs[mid]
        val medianG = gs[mid]
        val medianB = bs[mid]
        val brightness = (medianR + medianG + medianB) / 3.0

        return MedianColorResult(medianR, medianG, medianB, brightness < 90.0)
    }
}
