package com.paneling.models

import kotlinx.serialization.Serializable

@Serializable
data class ComicProgress(
    val bookId: String,
    val currentPageIndex: Int = 0,
    val currentPanelIndex: Int = 0,
    val isCompleted: Boolean = false,
    val lastReadDate: Long = 0L
)
