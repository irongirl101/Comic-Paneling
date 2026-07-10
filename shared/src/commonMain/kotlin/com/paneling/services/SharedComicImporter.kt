package com.paneling.services

import com.paneling.models.ComicBook
import com.paneling.models.ComicPage
import com.paneling.models.ComicPanel
import com.paneling.models.ReadingDirection

object SharedComicImporter {

    interface PlatformBridge {
        fun unzip(zipFilePath: String, destFolder: String): List<String>
        fun getPixels(imagePath: String): PixelData?
        fun generateUuid(): String
    }

    class PixelData(val raw: ByteArray, val width: Int, val height: Int, val bytesPerRow: Int)

    fun importComic(
        bridge: PlatformBridge,
        zipFilePath: String,
        destFolder: String,
        title: String,
        author: String = "Unknown",
        direction: ReadingDirection = ReadingDirection.LEFT_TO_RIGHT
    ): ComicBook {
        val imagePaths = bridge.unzip(zipFilePath, destFolder)

        val pages = imagePaths.mapIndexed { index, path ->
            val pixels = bridge.getPixels(path)
            val panels = if (pixels != null) {
                PanelDetector.detectPanels(
                    raw = pixels.raw,
                    width = pixels.width,
                    height = pixels.height,
                    bytesPerRow = pixels.bytesPerRow,
                    direction = direction
                ).mapIndexed { pIndex, rect ->
                    ComicPanel(
                        id = bridge.generateUuid(),
                        rect = rect,
                        order = pIndex
                    )
                }
            } else {
                emptyList()
            }

            ComicPage(
                id = bridge.generateUuid(),
                pageNumber = index + 1,
                imagePath = path,
                panels = panels
            )
        }

        return ComicBook(
            id = bridge.generateUuid(),
            title = title,
            author = author,
            coverImagePath = pages.firstOrNull()?.imagePath ?: "",
            readingDirection = direction,
            pages = pages
        )
    }
}
