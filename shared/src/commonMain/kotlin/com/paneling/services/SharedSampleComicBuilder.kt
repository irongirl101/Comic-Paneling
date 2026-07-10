package com.paneling.services

import com.paneling.models.ComicBook
import com.paneling.models.ComicPage
import com.paneling.models.ComicPanel
import com.paneling.models.ReadingDirection
import com.paneling.models.RectF

object SharedSampleComicBuilder {
    interface PlatformBridge {
        fun findResourcePath(subpath: String): String
        fun generateUuid(): String
    }

    fun buildSampleComics(bridge: PlatformBridge): List<ComicBook> {
        val antigravityId = "11111111-1111-1111-1111-111111111111"
        val agCover = bridge.findResourcePath("SampleComics/antigravity/cover.png")
        val agPage1 = bridge.findResourcePath("SampleComics/antigravity/page1.png")

        val agPages = listOf(
            ComicPage(
                id = "11111111-1111-1111-1111-222222222222",
                pageNumber = 1,
                imagePath = agPage1,
                panels = listOf(
                    ComicPanel(id = bridge.generateUuid(), rect = RectF(0.04, 0.04, 0.92, 0.28), order = 0),
                    ComicPanel(id = bridge.generateUuid(), rect = RectF(0.04, 0.35, 0.92, 0.30), order = 1),
                    ComicPanel(id = bridge.generateUuid(), rect = RectF(0.04, 0.68, 0.92, 0.28), order = 2)
                ),
                isCustomImported = false
            )
        )

        return listOf(
            ComicBook(
                id = antigravityId,
                title = "Antigravity Man",
                author = "Google DeepMind",
                coverImagePath = agCover,
                readingDirection = ReadingDirection.LEFT_TO_RIGHT,
                pages = agPages,
                isCustomImported = false
            )
        )
    }
}
