package com.trae.twotones

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.viewmodel.compose.viewModel

@Composable
fun GameView(engine: GameEngine = viewModel()) {
    val state by engine.state.collectAsState()
    val density = LocalDensity.current
    
    BoxWithConstraints(modifier = Modifier.fillMaxSize()) {
        val maxWidthPx = with(density) { maxWidth.toPx().toDouble() }
        val maxHeightPx = with(density) { maxHeight.toPx().toDouble() }
        
        LaunchedEffect(maxWidthPx, maxHeightPx) {
            engine.setDimensions(maxWidthPx, maxHeightPx)
        }

        // Background
        Box(modifier = Modifier.fillMaxSize().background(Color(0xFF1A1A1A)))

        // Game Render Loop (Canvas)
        if (state == GameState.PLAYING || state == GameState.GAMEOVER || state == GameState.LEVEL_COMPLETE) {
            GameCanvas(engine, Modifier.fillMaxSize())
        }

        // UI Overlay
        UiOverlay(engine)

        // Input Layer (Transparent)
        if (state == GameState.PLAYING) {
            InputLayer(engine)
        }
    }
}

@Composable
fun GameCanvas(engine: GameEngine, modifier: Modifier) {
    val obstacles by engine.obstacles.collectAsState()
    val player by engine.player.collectAsState()
    val state by engine.state.collectAsState()
    
    Canvas(modifier = modifier) {
        // Draw Obstacles
        obstacles.forEach { obs ->
            var obsColor = Color.White
            if (obs.type == ObstacleType.VARIABLE_SPEED) {
                obsColor = Color.Yellow
            }
            
            if (obs.type == ObstacleType.ROTATING || obs.type == ObstacleType.DIAGONAL) {
                rotate(degrees = Math.toDegrees(obs.rotation).toFloat(), pivot = Offset((obs.x + obs.width/2).toFloat(), (obs.y + obs.height/2).toFloat())) {
                    drawRect(
                        color = obsColor,
                        topLeft = Offset(obs.x.toFloat(), obs.y.toFloat()),
                        size = Size(obs.width.toFloat(), obs.height.toFloat())
                    )
                }
            } else if (obs.type == ObstacleType.CROSS) {
                 // Horizontal
                 drawRect(
                     color = obsColor,
                     topLeft = Offset(obs.x.toFloat(), (obs.y + obs.height/3).toFloat()),
                     size = Size(obs.width.toFloat(), (obs.height/3).toFloat())
                 )
                 // Vertical
                 drawRect(
                     color = obsColor,
                     topLeft = Offset((obs.x + obs.width/2 - 15).toFloat(), obs.y.toFloat()),
                     size = Size(30f, obs.height.toFloat())
                 )
            } else {
                drawRect(
                    color = obsColor,
                    topLeft = Offset(obs.x.toFloat(), obs.y.toFloat()),
                    size = Size(obs.width.toFloat(), obs.height.toFloat())
                )
            }
        }
        
        // Draw Player
        if (state == GameState.PLAYING || state == GameState.GAMEOVER) {
            val centerX = size.width / 2
            val centerY = size.height * 0.8f
            
            // Ring
            drawCircle(
                color = Color.White.copy(alpha = 0.1f),
                radius = player.radius.toFloat(),
                center = Offset(centerX, centerY),
                style = Stroke(width = 2f)
            )
            
            // Balls
            val x1 = centerX + kotlin.math.cos(player.angle) * player.radius
            val y1 = centerY + kotlin.math.sin(player.angle) * player.radius
            
            val x2 = centerX + kotlin.math.cos(player.angle + Math.PI) * player.radius
            val y2 = centerY + kotlin.math.sin(player.angle + Math.PI) * player.radius
            
            drawCircle(
                color = Color(0xFFFF3B30),
                radius = player.ballRadius.toFloat(),
                center = Offset(x1.toFloat(), y1.toFloat())
            )
            
            drawCircle(
                color = Color(0xFF007AFF),
                radius = player.ballRadius.toFloat(),
                center = Offset(x2.toFloat(), y2.toFloat())
            )
        }
    }
}

@Composable
fun InputLayer(engine: GameEngine) {
    var leftDown by remember { mutableStateOf(false) }
    var rightDown by remember { mutableStateOf(false) }
    
    LaunchedEffect(leftDown, rightDown) {
        engine.handleInput(leftDown, rightDown)
    }
    
    Row(modifier = Modifier.fillMaxSize()) {
        TouchBox(
            modifier = Modifier.weight(1f).fillMaxSize(),
            onDownChange = { leftDown = it }
        )
        TouchBox(
            modifier = Modifier.weight(1f).fillMaxSize(),
            onDownChange = { rightDown = it }
        )
    }
}

@Composable
fun TouchBox(modifier: Modifier, onDownChange: (Boolean) -> Unit) {
    Box(
        modifier = modifier.pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) {
                    val event = awaitPointerEvent()
                    val isDown = event.changes.any { it.pressed }
                    onDownChange(isDown)
                }
            }
        }
    )
}

@Composable
fun UiOverlay(engine: GameEngine) {
    val state by engine.state.collectAsState()
    val score by engine.score.collectAsState()
    val currentLevelIndex by engine.currentLevelIndex.collectAsState()
    val levels = engine.levels
    val unlockedLevel by engine.unlockedLevel.collectAsState()
    val highScore by engine.highScore.collectAsState()
    val scoreMultiplier = engine.scoreMultiplier
    
    if (state == GameState.MENU) {
        Column(
            modifier = Modifier.fillMaxSize().padding(bottom = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Spacer(Modifier.weight(1f))
            
            // Logo
            Box(modifier = Modifier
                .size(80.dp)
                .rotate(-45f)
            ) {
                Canvas(modifier = Modifier.fillMaxSize()) {
                    drawCircle(color = Color.White.copy(alpha = 0.2f), style = Stroke(width = 8f))
                    drawCircle(color = Color(0xFFFF3B30), radius = 20f, center = center + Offset(40f, 0f))
                    drawCircle(color = Color(0xFF007AFF), radius = 20f, center = center + Offset(-40f, 0f))
                }
            }
            
            Spacer(Modifier.height(20.dp))
            
            Text("TWO TONES", fontSize = 50.sp, fontWeight = FontWeight.Bold, color = Color.White)
            
            Spacer(Modifier.height(40.dp))
            
            Button(
                onClick = { engine.startLevel(0) },
                colors = ButtonDefaults.buttonColors(containerColor = Color.White),
                modifier = Modifier.width(200.dp).height(60.dp)
            ) {
                Text("PLAY", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color.Black)
            }
            
            Spacer(Modifier.height(20.dp))
            
            Button(
                onClick = { engine.setStateLevelSelect() },
                colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                border = androidx.compose.foundation.BorderStroke(2.dp, Color.White),
                modifier = Modifier.width(200.dp).height(50.dp)
            ) {
                Text("LEVELS", fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
            
            Spacer(Modifier.weight(1f))
        }
    } else if (state == GameState.LEVEL_SELECT) {
        Column(
            modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.9f)),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text("SELECT LEVEL", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = Color.White, modifier = Modifier.padding(top = 60.dp))
            
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 100.dp),
                modifier = Modifier.weight(1f).padding(20.dp),
                verticalArrangement = Arrangement.spacedBy(20.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp)
            ) {
                items(levels) { level ->
                    val isLocked = level.id > unlockedLevel
                    Box(
                        modifier = Modifier
                            .height(100.dp)
                            .clip(RoundedCornerShape(15.dp))
                            .background(if (isLocked) Color.Gray.copy(alpha = 0.3f) else Color.White.copy(alpha = 0.2f))
                            .clickable(enabled = !isLocked) { engine.startLevel(level.id - 1) },
                        contentAlignment = Alignment.Center
                    ) {
                        if (isLocked) {
                            Icon(Icons.Default.Lock, contentDescription = "Locked", tint = Color.Gray)
                        } else {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Text("${level.id}", fontSize = 40.sp, fontWeight = FontWeight.Bold, color = Color.White)
                                Text(level.name, fontSize = 12.sp, color = Color.White.copy(alpha = 0.8f))
                            }
                        }
                    }
                }
            }
            
            Button(
                onClick = { engine.setStateMenu() },
                colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                modifier = Modifier.padding(bottom = 40.dp)
            ) {
                Text("BACK", fontSize = 16.sp, fontWeight = FontWeight.Bold, color = Color.White)
            }
        }
    } else if (state == GameState.PLAYING) {
        // HUD
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 60.dp, start = 20.dp, end = 20.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.1f))
                        .clickable { engine.quitGame() },
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Default.Home, contentDescription = "Home", tint = Color.White.copy(alpha = 0.8f))
                }
                
                Column {
                    Text(levels[currentLevelIndex].name, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color.Gray)
                    Text("${score / 10}", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Color.White)
                }
            }
            
            levels[currentLevelIndex].targetScore?.let { target ->
                Column(horizontalAlignment = Alignment.End) {
                    Text("Target", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Color.Gray)
                    Text("${target / 10}", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Color.White)
                }
            }
        }
        
        if (scoreMultiplier > 1) {
             Box(modifier = Modifier.fillMaxSize().padding(top = 120.dp), contentAlignment = Alignment.TopCenter) {
                 Text("2x SCORE!", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Color.Yellow)
             }
        }
    } else if (state == GameState.LEVEL_COMPLETE) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.8f))
                .clickable { engine.handleInput(true, false) }, // Tap to continue
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("LEVEL COMPLETE", fontSize = 36.sp, fontWeight = FontWeight.Bold, color = Color.Yellow)
                Text("Score: ${score / 10}", fontSize = 20.sp, color = Color.White)
                Spacer(Modifier.height(40.dp))
                Text("Tap for Next Level", fontSize = 16.sp, color = Color.White)
            }
        }
    } else if (state == GameState.GAMEOVER) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.8f))
                .clickable { engine.handleInput(true, false) }, // Tap to restart
            contentAlignment = Alignment.Center
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("GAME OVER", fontSize = 40.sp, fontWeight = FontWeight.Bold, color = Color.White)
                Text("Score: ${score / 10}", fontSize = 20.sp, color = Color.White)
                if (highScore > 0) {
                    Text("Best: ${highScore / 10}", fontSize = 16.sp, color = Color.Yellow)
                }
                Spacer(Modifier.height(40.dp))
                Text("Tap to Restart", fontSize = 16.sp, color = Color.White)
            }
        }
    }
}
