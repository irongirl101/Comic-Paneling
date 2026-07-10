package com.paneling.services

import com.paneling.models.ComicProgress
import kotlinx.serialization.json.Json
import kotlinx.serialization.builtins.ListSerializer

object SharedReadingProgressManager {
    interface StorageBridge {
        fun getString(key: String): String?
        fun putString(key: String, value: String?)
        fun getCurrentTimeMs(): Long
    }

    private val json = Json { ignoreUnknownKeys = true }
    private const val STORAGE_KEY = "comic_panel_reader_progress"

    fun loadProgress(bridge: StorageBridge): Map<String, ComicProgress> {
        val raw = bridge.getString(STORAGE_KEY) ?: return emptyMap()
        return try {
            val list = json.decodeFromString(ListSerializer(ComicProgress.serializer()), raw)
            list.associateBy { it.bookId }
        } catch (e: Exception) {
            emptyMap()
        }
    }

    fun saveProgress(bridge: StorageBridge, progresses: Collection<ComicProgress>) {
        try {
            val raw = json.encodeToString(ListSerializer(ComicProgress.serializer()), progresses.toList())
            bridge.putString(STORAGE_KEY, raw)
        } catch (e: Exception) {
            // ignore
        }
    }
}
