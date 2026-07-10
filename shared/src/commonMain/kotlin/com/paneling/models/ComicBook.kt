package com.paneling.models

import kotlinx.serialization.Serializable

@Serializable
data class PointF(val x: Double, val y: Double)

@Serializable
data class RectF(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = x
    val maxX: Double get() = x + width
    val minY: Double get() = y
    val maxY: Double get() = y + height
    val midX: Double get() = x + width / 2.0
    val midY: Double get() = y + height / 2.0
    
    fun intersection(other: RectF): RectF {
        val rx1 = maxOf(minX, other.minX)
        val ry1 = maxOf(minY, other.minY)
        val rx2 = minOf(maxX, other.maxX)
        val ry2 = minOf(maxY, other.maxY)
        if (rx1 < rx2 && ry1 < ry2) {
            return RectF(rx1, ry1, rx2 - rx1, ry2 - ry1)
        }
        return RectF(0.0, 0.0, 0.0, 0.0)
    }
    
    val isNull: Boolean get() = width <= 0.0 || height <= 0.0
}

@Serializable
enum class ReadingDirection(val value: String) {
    LEFT_TO_RIGHT("Left to Right"),
    RIGHT_TO_LEFT("Right to Left (Manga)")
}

@Serializable
data class ComicPanel(
    val id: String,
    val rect: RectF,
    val order: Int,
    val polygonPoints: List<PointF>? = null
) {
    fun getPoints(): List<PointF> {
        if (polygonPoints != null && polygonPoints.size == 4) {
            return polygonPoints
        }
        return listOf(
            PointF(rect.minX, rect.minY),
            PointF(rect.maxX, rect.minY),
            PointF(rect.maxX, rect.maxY),
            PointF(rect.minX, rect.maxY)
        )
    }
}

@Serializable
data class ComicPage(
    val id: String,
    val pageNumber: Int,
    val imagePath: String,
    val panels: List<ComicPanel> = emptyList(),
    val isCustomImported: Boolean = false
)

@Serializable
data class ComicBook(
    val id: String,
    val title: String,
    val author: String,
    val coverImagePath: String,
    val readingDirection: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT,
    val pages: List<ComicPage> = emptyList(),
    val isCustomImported: Boolean = false
) {
    val totalPanelsCount: Int
        get() = pages.sumOf { it.panels.size }
}
