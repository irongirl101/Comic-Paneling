package com.paneling.android

import android.content.Context
import com.github.junrar.Archive
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.paneling.models.*
import com.paneling.services.*
import kotlinx.serialization.json.Json
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

enum class AppScreen {
    LIBRARY, READER
}

enum class ReaderViewMode {
    GUIDED, FOCUS
}

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    background = Color(0xFF08080C),
                    surface = Color(0xFF12121A),
                    primary = Color(0xFF6366F1),
                    onBackground = Color.White,
                    onSurface = Color.White
                )
            ) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    PanelsAppContainer()
                }
            }
        }
    }
}

class AndroidPlatformBridge(private val context: Context) : SharedComicImporter.PlatformBridge {
    override fun unzip(zipFilePath: String, destFolder: String): List<String> {
        val destDir = File(destFolder)
        destDir.mkdirs()
        
        val imageFiles = mutableListOf<File>()
        val isRar = zipFilePath.lowercase().let { it.endsWith(".rar") || it.endsWith(".cbr") }
        
        if (isRar) {
            val rarFile = File(zipFilePath)
            Archive(rarFile).use { archive ->
                for (fileHeader in archive) {
                    if (fileHeader.isDirectory) continue
                    
                    val path = fileHeader.fileName
                    val filename = File(path).name
                    
                    if (path.contains("__MACOSX", ignoreCase = true) || filename.startsWith(".")) {
                        continue
                    }
                    
                    val lowerName = filename.lowercase()
                    if (lowerName.endsWith(".jpg") || lowerName.endsWith(".jpeg") || lowerName.endsWith(".png") || lowerName.endsWith(".webp")) {
                        val flatName = path.replace('/', '_').replace('\\', '_')
                        val outFile = File(destDir, flatName)
                        
                        archive.getInputStream(fileHeader).use { input ->
                            outFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        imageFiles.add(outFile)
                    }
                }
            }
        } else {
            val zipFile = java.util.zip.ZipFile(zipFilePath)
            try {
                val entries = zipFile.entries()
                while (entries.hasMoreElements()) {
                    val entry = entries.nextElement()
                    if (entry.isDirectory) continue
                    
                    val path = entry.name
                    val filename = File(path).name
                    
                    if (path.contains("__MACOSX", ignoreCase = true) || filename.startsWith(".")) {
                        continue
                    }
                    
                    val lowerName = filename.lowercase()
                    if (lowerName.endsWith(".jpg") || lowerName.endsWith(".jpeg") || lowerName.endsWith(".png") || lowerName.endsWith(".webp")) {
                        val flatName = path.replace('/', '_').replace('\\', '_')
                        val outFile = File(destDir, flatName)
                        
                        zipFile.getInputStream(entry).use { input ->
                            outFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        imageFiles.add(outFile)
                    }
                }
            } finally {
                zipFile.close()
            }
        }
        
        if (imageFiles.isEmpty()) {
            throw Exception("No valid image pages (.jpg, .png, .webp) found inside the archive")
        }
        
        // Natural numeric sorting for file names to keep page orders correct (e.g., 2 before 10)
        val naturalOrderComparator = Comparator<File> { f1, f2 ->
            val s1 = f1.name
            val s2 = f2.name
            val chunks1 = s1.split("(?<=\\D)(?=\\d)|(?<=\\d)(?=\\D)".toRegex())
            val chunks2 = s2.split("(?<=\\D)(?=\\d)|(?<=\\d)(?=\\D)".toRegex())
            var i = 0
            while (i < chunks1.size && i < chunks2.size) {
                val c1 = chunks1[i]
                val c2 = chunks2[i]
                if (c1 != c2) {
                    val isDigit1 = c1.all { it.isDigit() }
                    val isDigit2 = c2.all { it.isDigit() }
                    return@Comparator if (isDigit1 && isDigit2) {
                        c1.toLong().compareTo(c2.toLong())
                    } else {
                        c1.compareTo(c2)
                    }
                }
                i++
            }
            chunks1.size.compareTo(chunks2.size)
        }
        
        imageFiles.sortWith(naturalOrderComparator)
        return imageFiles.map { it.absolutePath }
    }

    override fun getPixels(imagePath: String): SharedComicImporter.PixelData? {
        val bitmap = BitmapFactory.decodeFile(imagePath) ?: return null
        
        val maxDimension = 1024
        val scale = Math.min(1f, maxDimension.toFloat() / Math.max(bitmap.width, bitmap.height))
        val targetW = Math.max(4, (bitmap.width * scale).toInt())
        val targetH = Math.max(4, (bitmap.height * scale).toInt())
        
        val scaledBitmap = Bitmap.createScaledBitmap(bitmap, targetW, targetH, true)
        
        val pixels = IntArray(targetW * targetH)
        scaledBitmap.getPixels(pixels, 0, targetW, 0, 0, targetW, targetH)
        
        val bytes = ByteArray(targetW * targetH * 4)
        for (i in 0 until targetW * targetH) {
            val color = pixels[i]
            val r = (color shr 16) and 0xFF
            val g = (color shr 8) and 0xFF
            val b = color and 0xFF
            val a = (color shr 24) and 0xFF
            
            bytes[i * 4] = r.toByte()
            bytes[i * 4 + 1] = g.toByte()
            bytes[i * 4 + 2] = b.toByte()
            bytes[i * 4 + 3] = a.toByte()
        }
        
        return SharedComicImporter.PixelData(
            raw = bytes,
            width = targetW,
            height = targetH,
            bytesPerRow = targetW * 4
        )
    }

    override fun generateUuid(): String {
        return UUID.randomUUID().toString()
    }
}

class AndroidStorageBridge(private val context: Context) : SharedReadingProgressManager.StorageBridge {
    private val prefs = context.getSharedPreferences("comic_progress_prefs", Context.MODE_PRIVATE)

    override fun getString(key: String): String? {
        return prefs.getString(key, null)
    }

    override fun putString(key: String, value: String?) {
        prefs.edit().putString(key, value).apply()
    }

    override fun getCurrentTimeMs(): Long {
        return System.currentTimeMillis()
    }
}

@Composable
fun PanelsAppContainer() {
    val context = LocalContext.current
    val storageBridge = remember { AndroidStorageBridge(context) }
    
    var currentScreen by remember { mutableStateOf(AppScreen.LIBRARY) }
    var activeBook by remember { mutableStateOf<ComicBook?>(null) }
    
    var importedComics by remember { mutableStateOf<List<ComicBook>>(emptyList()) }
    var progresses by remember { mutableStateOf<Map<String, ComicProgress>>(emptyMap()) }
    
    fun reloadComics() {
        importedComics = loadImportedComics(context)
        progresses = SharedReadingProgressManager.loadProgress(storageBridge)
    }
    
    LaunchedEffect(Unit) {
        reloadComics()
    }
    
    when (currentScreen) {
        AppScreen.LIBRARY -> {
            LibraryScreen(
                importedComics = importedComics,
                progresses = progresses,
                onBookSelected = { book ->
                    activeBook = book
                    currentScreen = AppScreen.READER
                },
                onImportSuccess = {
                    reloadComics()
                }
            )
        }
        AppScreen.READER -> {
            activeBook?.let { book ->
                ReaderScreen(
                    book = book,
                    initialProgress = progresses[book.id] ?: ComicProgress(bookId = book.id),
                    onSaveProgress = { progress ->
                        val currentList = progresses.toMutableMap()
                        currentList[book.id] = progress
                        progresses = currentList
                        SharedReadingProgressManager.saveProgress(storageBridge, progresses.values)
                    },
                    onBack = {
                        activeBook = null
                        currentScreen = AppScreen.LIBRARY
                        reloadComics()
                    }
                )
            } ?: run {
                currentScreen = AppScreen.LIBRARY
            }
        }
    }
}

fun loadImportedComics(context: Context): List<ComicBook> {
    val comicsDir = File(context.filesDir, "comics")
    if (!comicsDir.exists()) return emptyList()
    
    val list = mutableListOf<ComicBook>()
    val json = Json { ignoreUnknownKeys = true }
    
    comicsDir.listFiles()?.forEach { dir ->
        if (dir.isDirectory) {
            val metadataFile = File(dir, "metadata.json")
            if (metadataFile.exists()) {
                try {
                    val raw = metadataFile.readText()
                    var book = json.decodeFromString<ComicBook>(raw)
                    book = book.copy(
                        coverImagePath = File(dir, File(book.coverImagePath).name).absolutePath,
                        pages = book.pages.map { page ->
                            page.copy(imagePath = File(dir, File(page.imagePath).name).absolutePath)
                        }
                    )
                    list.add(book)
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
    }
    return list
}

@Composable
fun LibraryScreen(
    importedComics: List<ComicBook>,
    progresses: Map<String, ComicProgress>,
    onBookSelected: (ComicBook) -> Unit,
    onImportSuccess: () -> Unit
) {
    val context = LocalContext.current
    var isImporting by remember { mutableStateOf(false) }
    
    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        if (uri != null) {
            isImporting = true
            Thread {
                try {
                    var displayName = ""
                    context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIndex = cursor.getColumnIndex(android.provider.OpenableColumns.DISPLAY_NAME)
                            if (nameIndex != -1) {
                                displayName = cursor.getString(nameIndex)
                            }
                        }
                    }
                    if (displayName.isEmpty()) {
                        displayName = uri.lastPathSegment ?: "Imported Comic.zip"
                    }
                    val title = displayName.substringBeforeLast(".")
                    val extension = displayName.substringAfterLast(".", "zip").lowercase()
                    
                    val tempFile = File(context.cacheDir, "temp_import.$extension")
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        FileOutputStream(tempFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                    
                    val bookId = UUID.randomUUID().toString()
                    val destFolder = File(File(context.filesDir, "comics"), bookId)
                    destFolder.mkdirs()
                    
                    val bridge = AndroidPlatformBridge(context)
                    val book = SharedComicImporter.importComic(
                        bridge = bridge,
                        zipFilePath = tempFile.absolutePath,
                        destFolder = destFolder.absolutePath,
                        title = title
                    )
                    
                    val metadataFile = File(destFolder, "metadata.json")
                    val json = Json { prettyPrint = true }
                    metadataFile.writeText(json.encodeToString(ComicBook.serializer(), book))
                    
                    tempFile.delete()
                    
                    Handler(Looper.getMainLooper()).post {
                        isImporting = false
                        Toast.makeText(context, "Successfully imported '$title'", Toast.LENGTH_SHORT).show()
                        onImportSuccess()
                    }
                } catch (e: Exception) {
                    Log.e("ComicPaneling", "Import failed", e)
                    Handler(Looper.getMainLooper()).post {
                        isImporting = false
                        Toast.makeText(context, "Import failed: ${e.message}", Toast.LENGTH_LONG).show()
                    }
                }
            }.start()
        }
    }
    
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF08080C))
            .safeDrawingPadding()
            .padding(16.dp)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Image(
                    painter = painterResource(id = R.drawable.app_logo),
                    contentDescription = "App Logo",
                    modifier = Modifier
                        .size(40.dp)
                        .padding(end = 12.dp)
                )
                Column {
                    Text(
                        text = "All Comics",
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = "Import a .cbz or .cbr file to read",
                        fontSize = 11.sp,
                        color = Color.Gray
                    )
                }
            }
            
            Button(
                onClick = { filePickerLauncher.launch("*/*") },
                colors = ButtonDefaults.buttonColors(
                    containerColor = Color.White,
                    contentColor = Color(0xFF08080C)
                ),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
                shape = RoundedCornerShape(20.dp),
                enabled = !isImporting
            ) {
                if (isImporting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                        color = Color(0xFF08080C)
                    )
                } else {
                    Text("Import Comic", fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
        
        Spacer(modifier = Modifier.height(16.dp))
        
        LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 140.dp),
            contentPadding = PaddingValues(bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            if (importedComics.isEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Box(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 60.dp),
                        contentAlignment = Alignment.Center
                    ) {
                        Text(
                            text = "Your library is empty.\nTap 'Import Comic' above to start reading!",
                            color = Color.Gray,
                            fontSize = 13.sp,
                            textAlign = TextAlign.Center
                        )
                    }
                }
            } else {
                item(span = { GridItemSpan(maxLineSpan) }) {
                    Text(
                        text = "My Imports",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White.copy(alpha = 0.85f),
                        modifier = Modifier.padding(bottom = 8.dp)
                    )
                }
                items(importedComics) { book ->
                    ComicCard(book = book, progress = progresses[book.id], onClick = { onBookSelected(book) })
                }
            }
        }
    }
}

@Composable
fun ComicCard(
    book: ComicBook,
    progress: ComicProgress?,
    onClick: () -> Unit
) {
    val context = LocalContext.current
    val coverBitmap = remember(book.coverImagePath) {
        try {
            if (book.coverImagePath.startsWith("/")) {
                BitmapFactory.decodeFile(book.coverImagePath)
            } else {
                context.assets.open(book.coverImagePath).use {
                    BitmapFactory.decodeStream(it)
                }
            }
        } catch (e: Exception) {
            null
        }
    }
    
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(Color(0xFF12121A))
            .clickable(onClick = onClick)
            .border(1.dp, Color.White.copy(alpha = 0.05f), RoundedCornerShape(12.dp))
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(200.dp)
                .background(Color(0xFF1C1C28))
        ) {
            if (coverBitmap != null) {
                Image(
                    bitmap = coverBitmap.asImageBitmap(),
                    contentDescription = book.title,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize()
                )
            }
            
            progress?.let {
                val ratio = if (book.pages.isNotEmpty()) {
                    (it.currentPageIndex + 1).toFloat() / book.pages.size.toFloat()
                } else 0f
                LinearProgressIndicator(
                    progress = { ratio },
                    modifier = Modifier
                        .fillMaxWidth()
                        .align(Alignment.BottomCenter)
                        .height(3.dp),
                    color = Color(0xFF6366F1),
                    trackColor = Color.Transparent
                )
            }
        }
        
        Column(
            modifier = Modifier
                .padding(10.dp)
                .fillMaxWidth()
        ) {
            Text(
                text = book.title,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                text = book.author,
                fontSize = 10.sp,
                color = Color.Gray,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

@Composable
fun ReaderScreen(
    book: ComicBook,
    initialProgress: ComicProgress,
    onSaveProgress: (ComicProgress) -> Unit,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    var currentPageIndex by remember { mutableStateOf(initialProgress.currentPageIndex) }
    var currentPanelIndex by remember { mutableStateOf(initialProgress.currentPanelIndex) }
    var viewMode by remember { mutableStateOf(ReaderViewMode.GUIDED) }
    
    var showControls by remember { mutableStateOf(true) }
    var zoomFactor by remember { mutableStateOf(1f) }
    
    val currentPage = book.pages.getOrNull(currentPageIndex)
    
    fun saveProgress() {
        val completed = currentPageIndex >= book.pages.size - 1 && 
                currentPanelIndex >= (currentPage?.panels?.size ?: 1) - 1
        onSaveProgress(
            ComicProgress(
                bookId = book.id,
                currentPageIndex = currentPageIndex,
                currentPanelIndex = currentPanelIndex,
                isCompleted = completed,
                lastReadDate = System.currentTimeMillis()
            )
        )
    }
    
    fun goToNextPanel() {
        if (currentPage == null) return
        if (currentPanelIndex < currentPage.panels.size - 1) {
            currentPanelIndex++
            saveProgress()
        } else {
            if (currentPageIndex < book.pages.size - 1) {
                currentPageIndex++
                currentPanelIndex = 0
                saveProgress()
            }
        }
    }
    
    fun goToPreviousPanel() {
        if (currentPanelIndex > 0) {
            currentPanelIndex--
            saveProgress()
        } else {
            if (currentPageIndex > 0) {
                currentPageIndex--
                val prevPage = book.pages[currentPageIndex]
                currentPanelIndex = Math.max(0, prevPage.panels.size - 1)
                saveProgress()
            }
        }
    }
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
            .pointerInput(book.id, currentPageIndex) {
                awaitEachGesture {
                    var dragAccumulatedX = 0f
                    var isZooming = false
                    var isDragging = false
                    
                    val down = awaitFirstDown()
                    
                    do {
                        val event = awaitPointerEvent()
                        if (event.changes.size > 1) {
                            isZooming = true
                        }
                        
                        val panChange = event.calculatePan()
                        if (!isZooming && Math.abs(panChange.x) > 2f) {
                            isDragging = true
                            dragAccumulatedX += panChange.x
                        }
                        
                        val zoomChange = event.calculateZoom()
                        if (isZooming && zoomChange != 1f) {
                            zoomFactor = Math.min(3.0f, Math.max(0.5f, zoomFactor * zoomChange))
                        }
                        
                        event.changes.forEach { it.consume() }
                    } while (event.changes.any { it.pressed })
                    
                    if (!isZooming && !isDragging) {
                        showControls = !showControls
                    } else if (isDragging && !isZooming) {
                        val swipeThreshold = 100f
                        if (dragAccumulatedX > swipeThreshold) {
                            if (book.readingDirection == ReadingDirection.RIGHT_TO_LEFT) {
                                goToNextPanel()
                            } else {
                                goToPreviousPanel()
                            }
                        } else if (dragAccumulatedX < -swipeThreshold) {
                            if (book.readingDirection == ReadingDirection.RIGHT_TO_LEFT) {
                                goToPreviousPanel()
                            } else {
                                goToNextPanel()
                            }
                        }
                    }
                }
            }
    ) {
        if (currentPage != null) {
            val bitmap = remember(currentPage.imagePath) {
                try {
                    if (currentPage.imagePath.startsWith("/")) {
                        BitmapFactory.decodeFile(currentPage.imagePath)
                    } else {
                        context.assets.open(currentPage.imagePath).use {
                            BitmapFactory.decodeStream(it)
                        }
                    }
                } catch (e: Exception) {
                    null
                }
            }
            
            if (bitmap != null) {
                when (viewMode) {
                    ReaderViewMode.GUIDED -> {
                        GuidedSpotlightView(
                            bitmap = bitmap,
                            page = currentPage,
                            activePanelIndex = currentPanelIndex,
                            zoomFactor = zoomFactor,
                            onZoomChange = { zoomFactor = it }
                        )
                    }
                    ReaderViewMode.FOCUS -> {
                        FocusedCropView(
                            bitmap = bitmap,
                            page = currentPage,
                            activePanelIndex = currentPanelIndex,
                            zoomFactor = zoomFactor,
                            onZoomChange = { zoomFactor = it }
                        )
                    }
                }
            }
        }
        
        // HUD Overlay Top Bar
        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        brush = Brush.verticalGradient(
                            colors = listOf(Color.Black.copy(alpha = 0.85f), Color.Transparent)
                        )
                    )
                    .statusBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 20.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween
            ) {
                Text(
                    text = "Back",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clickable { onBack() }
                        .padding(8.dp)
                )
                
                Text(
                    text = book.title,
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 16.dp)
                )
                
                Text(
                    text = if (viewMode == ReaderViewMode.GUIDED) "Spotlight" else "Crop",
                    color = Color(0xFF6366F1),
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier
                        .clickable {
                            viewMode = if (viewMode == ReaderViewMode.GUIDED) ReaderViewMode.FOCUS else ReaderViewMode.GUIDED
                        }
                        .padding(8.dp)
                )
            }
        }
        
        // HUD Overlay Bottom Bar
        AnimatedVisibility(
            visible = showControls,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.BottomCenter)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        brush = Brush.verticalGradient(
                            colors = listOf(Color.Transparent, Color.Black.copy(alpha = 0.85f))
                        )
                    )
                    .navigationBarsPadding()
                    .padding(horizontal = 16.dp, vertical = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = "Page ${currentPageIndex + 1} of ${book.pages.size} — Panel ${currentPanelIndex + 1} of ${currentPage?.panels?.size ?: 0}",
                    color = Color.White,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium
                )
                
                Spacer(modifier = Modifier.height(10.dp))
                
                Slider(
                    value = currentPageIndex.toFloat(),
                    onValueChange = {
                        currentPageIndex = it.toInt()
                        currentPanelIndex = 0
                        saveProgress()
                    },
                    valueRange = 0f..Math.max(0f, (book.pages.size - 1).toFloat()),
                    colors = SliderDefaults.colors(
                        activeTrackColor = Color(0xFF6366F1),
                        thumbColor = Color.White
                    )
                )
            }
        }
    }
}

@Composable
fun GuidedSpotlightView(
    bitmap: Bitmap,
    page: ComicPage,
    activePanelIndex: Int,
    zoomFactor: Float,
    onZoomChange: (Float) -> Unit
) {
    var containerSize by remember { mutableStateOf(IntSize(0, 0)) }
    
    val activePanel = page.panels.getOrNull(activePanelIndex) ?: ComicPanel(id = "fallback", rect = RectF(0.0, 0.0, 1.0, 1.0), order = 0)
    val panelRect = activePanel.rect
    
    val px = panelRect.x.toFloat()
    val py = panelRect.y.toFloat()
    val pw = panelRect.width.toFloat()
    val ph = panelRect.height.toFloat()
    
    val fitW: Float
    val fitH: Float
    val dx: Float
    val dy: Float
    
    if (containerSize.width > 0 && containerSize.height > 0) {
        val scale = kotlin.math.min(containerSize.width.toFloat() / bitmap.width, containerSize.height.toFloat() / bitmap.height)
        fitW = bitmap.width * scale
        fitH = bitmap.height * scale
        dx = (containerSize.width - fitW) / 2f
        dy = (containerSize.height - fitH) / 2f
    } else {
        fitW = 1f
        fitH = 1f
        dx = 0f
        dy = 0f
    }
    
    val panelWidthOnScreen = pw * fitW
    val panelHeightOnScreen = ph * fitH
    
    val targetScaleX = if (panelWidthOnScreen > 0) containerSize.width.toFloat() / panelWidthOnScreen else 1f
    val targetScaleY = if (panelHeightOnScreen > 0) containerSize.height.toFloat() / panelHeightOnScreen else 1f
    val targetScale = kotlin.math.min(4.5f, kotlin.math.max(1.0f, kotlin.math.min(targetScaleX, targetScaleY))) * zoomFactor
    
    val pMidX = (px + pw / 2f - 0.5f) * fitW
    val pMidY = (py + ph / 2f - 0.5f) * fitH
    
    val offsetX = -pMidX * targetScale
    val offsetY = -pMidY * targetScale
    
    val animatedScale by animateFloatAsState(targetValue = targetScale, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    val animatedOffsetX by animateFloatAsState(targetValue = offsetX, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    val animatedOffsetY by animateFloatAsState(targetValue = offsetY, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    
    val animatedPx by animateFloatAsState(targetValue = px, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    val animatedPy by animateFloatAsState(targetValue = py, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    val animatedPw by animateFloatAsState(targetValue = pw, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    val animatedPh by animateFloatAsState(targetValue = ph, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    
    val infiniteTransition = rememberInfiniteTransition()
    val borderPulse by infiniteTransition.animateFloat(
        initialValue = 0.7f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse
        )
    )
    
    val density = LocalDensity.current
    val widthDp = with(density) { fitW.toDp() }
    val heightDp = with(density) { fitH.toDp() }
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .onGloballyPositioned { containerSize = it.size }
    ) {
        if (containerSize.width > 0 && containerSize.height > 0) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = animatedScale
                        scaleY = animatedScale
                        translationX = animatedOffsetX
                        translationY = animatedOffsetY
                    }
            ) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier
                        .width(widthDp)
                        .height(heightDp)
                        .align(Alignment.Center)
                )
                
                Canvas(
                    modifier = Modifier
                        .width(widthDp)
                        .height(heightDp)
                        .align(Alignment.Center)
                ) {
                    val canvasPx = animatedPx * size.width
                    val canvasPy = animatedPy * size.height
                    val canvasPw = animatedPw * size.width
                    val canvasPh = animatedPh * size.height
                    
                    clipPath(
                        path = Path().apply {
                            addRect(androidx.compose.ui.geometry.Rect(canvasPx, canvasPy, canvasPx + canvasPw, canvasPy + canvasPh))
                        },
                        clipOp = ClipOp.Difference
                    ) {
                        drawRect(Color.Black.copy(alpha = 0.85f))
                    }
                    
                    drawRect(
                        color = Color.White.copy(alpha = borderPulse),
                        topLeft = Offset(canvasPx, canvasPy),
                        size = Size(canvasPw, canvasPh),
                        style = Stroke(width = 2.5f / animatedScale)
                    )
                }
            }
        }
    }
}

@Composable
fun FocusedCropView(
    bitmap: Bitmap,
    page: ComicPage,
    activePanelIndex: Int,
    zoomFactor: Float,
    onZoomChange: (Float) -> Unit
) {
    var containerSize by remember { mutableStateOf(IntSize(0, 0)) }
    
    val activePanel = page.panels.getOrNull(activePanelIndex) ?: ComicPanel(id = "fallback", rect = RectF(0.0, 0.0, 1.0, 1.0), order = 0)
    val panelRect = activePanel.rect
    
    val px = panelRect.x.toFloat()
    val py = panelRect.y.toFloat()
    val pw = panelRect.width.toFloat()
    val ph = panelRect.height.toFloat()
    
    val fitW: Float
    val fitH: Float
    
    if (containerSize.width > 0 && containerSize.height > 0) {
        val scale = kotlin.math.min(containerSize.width.toFloat() / bitmap.width, containerSize.height.toFloat() / bitmap.height)
        fitW = bitmap.width * scale
        fitH = bitmap.height * scale
    } else {
        fitW = 1f
        fitH = 1f
    }
    
    val panelWidthOnScreen = pw * fitW
    val panelHeightOnScreen = ph * fitH
    
    val targetScaleX = if (panelWidthOnScreen > 0) containerSize.width.toFloat() / panelWidthOnScreen else 1f
    val targetScaleY = if (panelHeightOnScreen > 0) containerSize.height.toFloat() / panelHeightOnScreen else 1f
    val targetScale = kotlin.math.min(4.5f, kotlin.math.max(1.0f, kotlin.math.min(targetScaleX, targetScaleY))) * zoomFactor
    
    val pMidX = (px + pw / 2f - 0.5f) * fitW
    val pMidY = (py + ph / 2f - 0.5f) * fitH
    
    val offsetX = -pMidX * targetScale
    val offsetY = -pMidY * targetScale
    
    val animatedScale by animateFloatAsState(targetValue = targetScale, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    val animatedOffsetX by animateFloatAsState(targetValue = offsetX, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    val animatedOffsetY by animateFloatAsState(targetValue = offsetY, animationSpec = spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessMediumLow))
    
    val density = LocalDensity.current
    val widthDp = with(density) { fitW.toDp() }
    val heightDp = with(density) { fitH.toDp() }
    
    Box(
        modifier = Modifier
            .fillMaxSize()
            .onGloballyPositioned { containerSize = it.size }
    ) {
        if (containerSize.width > 0 && containerSize.height > 0) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        scaleX = animatedScale
                        scaleY = animatedScale
                        translationX = animatedOffsetX
                        translationY = animatedOffsetY
                    }
            ) {
                Image(
                    bitmap = bitmap.asImageBitmap(),
                    contentDescription = null,
                    modifier = Modifier
                        .width(widthDp)
                        .height(heightDp)
                        .align(Alignment.Center)
                )
            }
        }
    }
}
