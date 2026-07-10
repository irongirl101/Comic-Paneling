package com.paneling.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.unit.dp
import com.paneling.models.ReadingDirection
import com.paneling.models.RectF
import com.paneling.services.PanelDetector

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    PanelVerifierScreen()
                }
            }
        }
    }
}

@Composable
fun PanelVerifierScreen() {
    var detectedPanels by remember { mutableStateOf<List<RectF>>(emptyList()) }
    var statusMessage by remember { mutableStateOf("Tap 'Detect' to run KMP algorithm on mock page") }

    val W = 100
    val H = 100
    val bpp = 4
    val bpr = W * bpp

    val rawPixels = remember {
        ByteArray(H * bpr).apply {
            for (i in indices step 4) {
                this[i] = 255.toByte()
                this[i + 1] = 255.toByte()
                this[i + 2] = 255.toByte()
                this[i + 3] = 255.toByte()
            }
            fun drawPanel(x1: Int, x2: Int, y1: Int, y2: Int) {
                for (y in y1..y2) {
                    for (x in x1..x2) {
                        val o = y * bpr + x * bpp
                        this[o] = 100.toByte()
                        this[o + 1] = 100.toByte()
                        this[o + 2] = 100.toByte()
                    }
                }
            }
            drawPanel(10, 40, 10, 40)
            drawPanel(60, 90, 10, 40)
            drawPanel(10, 40, 60, 90)
            drawPanel(60, 90, 60, 90)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text(
            text = "Panels KMP Android Verifier",
            style = MaterialTheme.typography.headlineMedium
        )

        Text(
            text = statusMessage,
            style = MaterialTheme.typography.bodyMedium
        )

        Box(
            modifier = Modifier
                .size(300.dp)
                .background(Color.White)
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val scaleX = size.width / W
                val scaleY = size.height / H

                drawRect(Color(0xFF646464), Offset(10 * scaleX, 10 * scaleY), Size(30 * scaleX, 30 * scaleY))
                drawRect(Color(0xFF646464), Offset(60 * scaleX, 10 * scaleY), Size(30 * scaleX, 30 * scaleY))
                drawRect(Color(0xFF646464), Offset(10 * scaleX, 60 * scaleY), Size(30 * scaleX, 30 * scaleY))
                drawRect(Color(0xFF646464), Offset(60 * scaleX, 60 * scaleY), Size(30 * scaleX, 30 * scaleY))

                detectedPanels.forEachIndexed { _, rect ->
                    drawRect(
                        color = Color.Green,
                        topLeft = Offset(rect.x.toFloat() * size.width, rect.y.toFloat() * size.height),
                        size = Size(rect.width.toFloat() * size.width, rect.height.toFloat() * size.height),
                        style = Stroke(width = 3.dp.toPx())
                    )
                }
            }
        }

        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Button(
                onClick = {
                    val start = System.currentTimeMillis()
                    val panels = PanelDetector.detectPanels(
                        raw = rawPixels,
                        width = W,
                        height = H,
                        bytesPerRow = bpr,
                        direction = ReadingDirection.LEFT_TO_RIGHT,
                        mode = PanelDetector.DetectionMode.XYCUT
                    )
                    val duration = System.currentTimeMillis() - start
                    detectedPanels = panels
                    statusMessage = "XY-Cut found ${panels.size} panels in ${duration}ms"
                }
            ) {
                Text("Run XY-Cut")
            }

            Button(
                onClick = {
                    val start = System.currentTimeMillis()
                    val panels = PanelDetector.detectPanels(
                        raw = rawPixels,
                        width = W,
                        height = H,
                        bytesPerRow = bpr,
                        direction = ReadingDirection.LEFT_TO_RIGHT,
                        mode = PanelDetector.DetectionMode.CONTOUR
                    )
                    val duration = System.currentTimeMillis() - start
                    detectedPanels = panels
                    statusMessage = "Contour found ${panels.size} panels in ${duration}ms"
                }
            ) {
                Text("Run Contour")
            }
        }

        if (detectedPanels.isNotEmpty()) {
            Button(
                onClick = {
                    detectedPanels = emptyList()
                    statusMessage = "Cleared overlays"
                },
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.secondary)
            ) {
                Text("Clear Overlays")
            }
        }
    }
}
