package com.trae.twotones

import android.app.Application
import android.content.Context
import android.content.SharedPreferences
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.UUID
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

enum class GameState {
    MENU, LEVEL_SELECT, PLAYING, GAMEOVER, LEVEL_COMPLETE
}

enum class ObstacleType {
    RECTANGLE,
    L_SHAPE_LEFT,
    L_SHAPE_RIGHT,
    CROSS,
    VARIABLE_SPEED,
    SPLIT,
    ROTATING,
    VERTICAL,
    DIAGONAL
}

data class Level(
    val id: Int,
    val name: String,
    val targetScore: Int?, // null for endless
    val baseSpeed: Double,
    val spawnInterval: Double,
    val allowedTypes: List<ObstacleType>,
    val widthRatio: Double,
    val color: Long
)

data class Player(
    var angle: Double = 0.0,
    var radius: Double = 55.0,
    var ballRadius: Double = 12.0,
    val rotationSpeed: Double = 0.08
) {
    fun update(left: Boolean, right: Boolean) {
        if (left) angle -= rotationSpeed
        if (right) angle += rotationSpeed
    }
}

data class Obstacle(
    val id: UUID = UUID.randomUUID(),
    var x: Double,
    var y: Double,
    var width: Double,
    var height: Double = 20.0,
    var speed: Double,
    var type: ObstacleType = ObstacleType.RECTANGLE,
    var isSplit: Boolean = false,
    var splitOffset: Double = 0.0,
    var rotation: Double = 0.0,
    var rotationalSpeed: Double = 0.0
)

class GameEngine(application: Application) : AndroidViewModel(application) {

    private val prefs: SharedPreferences = application.getSharedPreferences("twotones", Context.MODE_PRIVATE)

    // State
    private val _state = MutableStateFlow(GameState.MENU)
    val state = _state.asStateFlow()

    private val _score = MutableStateFlow(0)
    val score = _score.asStateFlow()

    private val _highScore = MutableStateFlow(prefs.getInt("highscore", 0))
    val highScore = _highScore.asStateFlow()

    private val _unlockedLevel = MutableStateFlow(max(1, prefs.getInt("unlocked_level", 1)))
    val unlockedLevel = _unlockedLevel.asStateFlow()

    private val _currentLevelIndex = MutableStateFlow(0)
    val currentLevelIndex = _currentLevelIndex.asStateFlow()

    // Entities
    private val _player = MutableStateFlow(Player())
    val player = _player.asStateFlow()

    private val _obstacles = MutableStateFlow<List<Obstacle>>(emptyList())
    val obstacles = _obstacles.asStateFlow()
    
    // UI Helpers (Not strictly state but useful for UI)
    val levels: List<Level> = listOf(
        Level(1, "Level 1", 200, 4.0, 100.0, listOf(ObstacleType.RECTANGLE, ObstacleType.VERTICAL, ObstacleType.ROTATING), 0.6, 0xFF1A1A1A),
        Level(2, "Level 2", 400, 3.5, 90.0, listOf(ObstacleType.RECTANGLE, ObstacleType.VERTICAL, ObstacleType.ROTATING, ObstacleType.DIAGONAL, ObstacleType.L_SHAPE_LEFT, ObstacleType.L_SHAPE_RIGHT), 0.5, 0xFF2A1A1A),
        Level(3, "Level 3", 600, 3.0, 80.0, listOf(ObstacleType.RECTANGLE, ObstacleType.VERTICAL, ObstacleType.DIAGONAL, ObstacleType.CROSS, ObstacleType.ROTATING, ObstacleType.VARIABLE_SPEED), 0.45, 0xFF1A2A1A),
        Level(4, "Endless", null, 2.5, 70.0, listOf(ObstacleType.RECTANGLE, ObstacleType.VERTICAL, ObstacleType.DIAGONAL, ObstacleType.CROSS, ObstacleType.ROTATING, ObstacleType.VARIABLE_SPEED, ObstacleType.SPLIT), 0.4, 0xFF000000)
    )

    // Logic
    private var lastSafeZoneX: Double? = null
    private var consecutiveSafeZoneCount = 0
    private var consecutiveFailures = 0
    private var difficultyReduced = false
    private var obstaclesSinceFailure = 0
    
    var scoreMultiplier = 1
    var multiplierTimer = 0
    var emergencySpinsAvailable = 1

    // Input
    private var inputLeft = false
    private var inputRight = false

    // Loop
    private var gameLoopJob: Job? = null
    private var spawnTimer = 0
    private var currentSpawnInterval = 100.0
    private var currentBaseSpeed = 2.0
    
    var width: Double = 0.0
    var height: Double = 0.0
    var gameOverTimer = 0

    // Audio & Haptics
    private var mediaPlayer: MediaPlayer? = null
    private val vibrator = application.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator

    init {
        setupAudio()
    }

    private fun setupAudio() {
        // Try to load bgm from raw resource if available. 
        // Note: User needs to put bgm.mp3 in res/raw/bgm.mp3
        try {
             val resId = getApplication<Application>().resources.getIdentifier("bgm", "raw", getApplication<Application>().packageName)
             if (resId != 0) {
                 mediaPlayer = MediaPlayer.create(getApplication(), resId)
                 mediaPlayer?.isLooping = true
                 mediaPlayer?.setVolume(0.5f, 0.5f)
             }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun setDimensions(w: Double, h: Double) {
        width = w
        height = h
        
        // Dynamic Sizing
        val scaleFactor = width / 375.0
        val p = _player.value
        _player.value = p.copy(
            radius = 55.0 * scaleFactor,
            ballRadius = 12.0 * scaleFactor
        )
    }

    fun handleInput(left: Boolean, right: Boolean) {
        val changed = (left != inputLeft) || (right != inputRight)
        inputLeft = left
        inputRight = right
        
        if (_state.value == GameState.PLAYING && changed && (left || right)) {
            vibrateLight()
        } else if (_state.value == GameState.GAMEOVER && gameOverTimer > 10 && (left || right)) {
            reset(_currentLevelIndex.value)
        } else if (_state.value == GameState.LEVEL_COMPLETE && (left || right)) {
             if (_currentLevelIndex.value + 1 < levels.size) {
                 startLevel(_currentLevelIndex.value + 1)
             } else {
                 _state.value = GameState.MENU
             }
        }
    }
    
    fun quitGame() {
        stopGameLoop()
        _state.value = GameState.MENU
        _obstacles.value = emptyList()
        inputLeft = false
        inputRight = false
    }

    fun startLevel(index: Int) {
        stopGameLoop()
        _currentLevelIndex.value = index
        reset(index)
        startGameLoop()
    }

    private fun reset(levelIndex: Int) {
        _state.value = GameState.PLAYING
        _score.value = 0
        _obstacles.value = emptyList()
        _player.value = _player.value.copy(angle = 0.0)
        spawnTimer = 0
        
        lastSafeZoneX = null
        consecutiveSafeZoneCount = 0
        scoreMultiplier = 1
        multiplierTimer = 0
        emergencySpinsAvailable = 1
        
        val safeIndex = max(0, min(levelIndex, levels.size - 1))
        _currentLevelIndex.value = safeIndex
        
        val level = levels[safeIndex]
        currentSpawnInterval = level.spawnInterval
        currentBaseSpeed = level.baseSpeed
        
        inputLeft = false
        inputRight = false
        
        if (width == 0.0) width = 1080.0 // Fallback
        if (height == 0.0) height = 1920.0
        
        mediaPlayer?.start()
    }
    
    private fun startGameLoop() {
        stopGameLoop()
        gameLoopJob = viewModelScope.launch {
            while (isActive) {
                update()
                delay(16) // ~60 FPS
            }
        }
    }

    private fun stopGameLoop() {
        gameLoopJob?.cancel()
        gameLoopJob = null
    }
    
    fun pauseGame() {
        stopGameLoop()
        mediaPlayer?.pause()
    }
    
    fun resumeGame() {
        if (_state.value == GameState.PLAYING) {
            startGameLoop()
            mediaPlayer?.start()
        }
    }

    private fun update() {
        if (_state.value == GameState.GAMEOVER || _state.value == GameState.LEVEL_COMPLETE) {
            gameOverTimer++
            return
        }
        if (_state.value != GameState.PLAYING) return
        
        // Level Complete Check
        val level = levels[_currentLevelIndex.value]
        if (level.targetScore != null && _score.value >= level.targetScore) {
            levelComplete()
            return
        }

        // Update Player
        val p = _player.value
        p.update(inputLeft, inputRight)
        // Need to force state flow update if using data class directly? 
        // StateFlow emits only if value changed. Mutating property inside data class won't trigger emit if ref is same.
        // We need to copy.
        _player.value = p.copy() 

        // Spawn Obstacles
        if (width > 0) {
            spawnTimer++
            if (spawnTimer.toDouble() > currentSpawnInterval) {
                spawnObstacle()
                spawnTimer = 0
                if (currentSpawnInterval > 40) currentSpawnInterval -= 0.05
            }
        }

        // Update Obstacles
        val currentObs = _obstacles.value.toMutableList()
        val iterator = currentObs.listIterator()
        var passedCount = 0
        
        while (iterator.hasNext()) {
            val obs = iterator.next()
            var newY = obs.y
            var newX = obs.x
            var newSpeed = obs.speed
            var newRotation = obs.rotation
            var newIsSplit = obs.isSplit
            
            // Variable Speed
            if (obs.type == ObstacleType.VARIABLE_SPEED) {
                if (obs.y > height / 2) {
                    newSpeed = height / (1.0 * 60)
                } else {
                    newSpeed = height / (2.0 * 60)
                }
            }
            
            newY += newSpeed
            
            // Split
            if (obs.type == ObstacleType.SPLIT && !obs.isSplit && obs.y > height / 2) {
                newX += obs.splitOffset
                newIsSplit = true
            }
            
            // Rotate
            if (obs.type == ObstacleType.ROTATING) {
                newRotation += 0.05
            }
            
            // Update obs
            val updatedObs = obs.copy(x = newX, y = newY, speed = newSpeed, rotation = newRotation, isSplit = newIsSplit)
            iterator.set(updatedObs)
            
            // Check passed
            if (updatedObs.y > height + 100) {
                passedCount++
                iterator.remove()
            }
        }
        
        _obstacles.value = currentObs

        // Scoring
        if (passedCount > 0) {
            _score.value += passedCount * scoreMultiplier
            
            if (_score.value % 10 == 0) {
                scoreMultiplier = 2
                multiplierTimer = 3
            } else if (multiplierTimer > 0) {
                multiplierTimer -= passedCount
                if (multiplierTimer <= 0) {
                    scoreMultiplier = 1
                    multiplierTimer = 0
                }
            }
            
            if (difficultyReduced) {
                obstaclesSinceFailure += passedCount
                if (obstaclesSinceFailure >= 3) {
                    difficultyReduced = false
                    obstaclesSinceFailure = 0
                }
            }
        }

        checkCollisions()
    }

    private fun spawnObstacle() {
        val p = _player.value
        val playerDiameter = p.radius * 2 + p.ballRadius * 2 + 20
        val minSafeZone = playerDiameter
        
        val level = levels[_currentLevelIndex.value]
        var obstacleWidthRatio = level.widthRatio
        var baseSpeedRatio = level.baseSpeed
        var allowedTypes = level.allowedTypes.toMutableList()
        var safeZoneRatio = 0.4
        
        if (difficultyReduced) {
            obstacleWidthRatio += 0.05
            baseSpeedRatio += 0.5
            safeZoneRatio += 0.1
        } else if (level.name == "Endless") {
             val ramping = min(_score.value.toDouble() / 500.0, 1.0)
             obstacleWidthRatio -= ramping * 0.1
             baseSpeedRatio -= ramping * 1.0
        }
        
        val type = allowedTypes.random()
        
        val margin = 25.0
        val playableWidth = width - (2 * margin)
        val obsSpeed = height / (baseSpeedRatio * 60)
        
        var targetObsWidth = width * obstacleWidthRatio
        var obsHeight = max(15.0, height * 0.03)
        
        if (type == ObstacleType.VERTICAL) {
            targetObsWidth = 30.0
            obsHeight = height * 0.25
        } else if (type == ObstacleType.DIAGONAL) {
            targetObsWidth = width * 0.4
            obsHeight = 20.0
        }
        
        val maxAllowedObsWidth = max(50.0, playableWidth - minSafeZone)
        val obsWidth = min(targetObsWidth, maxAllowedObsWidth)
        
        val safeZoneWidth = width * safeZoneRatio
        val actualSafeZoneWidth = max(safeZoneWidth, minSafeZone)
        val maxSafeX = width - actualSafeZoneWidth
        
        var safeZoneX = if (maxSafeX > 0) Random.nextDouble(0.0, maxSafeX) else 0.0
        
        // Overlap logic simplified for port
        lastSafeZoneX?.let { last ->
             val overlapStart = max(safeZoneX, last)
             val overlapEnd = min(safeZoneX + actualSafeZoneWidth, last + actualSafeZoneWidth)
             if (overlapEnd > overlapStart) consecutiveSafeZoneCount++ else consecutiveSafeZoneCount = 0
             
             if (consecutiveSafeZoneCount >= 3) {
                 if (last < width/2) {
                     val minX = width/2
                     val maxX = width - actualSafeZoneWidth
                     if (maxX > minX) safeZoneX = Random.nextDouble(minX, maxX) else safeZoneX = minX
                 } else {
                     val minX = 0.0
                     val maxX = width/2 - actualSafeZoneWidth
                     if (maxX > minX) safeZoneX = Random.nextDouble(minX, maxX) else safeZoneX = minX
                 }
                 consecutiveSafeZoneCount = 0
             }
        }
        lastSafeZoneX = safeZoneX
        
        var x: Double
        if (Random.nextBoolean()) {
            x = safeZoneX - obsWidth
            if (x < margin) {
                x = margin
                if (x + obsWidth > safeZoneX) x = safeZoneX + actualSafeZoneWidth
            }
        } else {
            x = safeZoneX + actualSafeZoneWidth
        }
        
        if (x < margin) x = margin
        if (x + obsWidth > width - margin) x = width - obsWidth - margin
        
        var obs = Obstacle(x = x, y = -100.0, width = obsWidth, height = obsHeight, speed = obsSpeed, type = type)
        
        if (type == ObstacleType.SPLIT) {
            obs = obs.copy(isSplit = true, splitOffset = Random.nextDouble(-20.0, 20.0))
        } else if (type == ObstacleType.ROTATING) {
            obs = obs.copy(rotationalSpeed = 0.05, rotation = Random.nextDouble(0.0, Math.PI))
        } else if (type == ObstacleType.DIAGONAL) {
             obs = obs.copy(rotation = if (Random.nextBoolean()) Math.PI/4 else -Math.PI/4, rotationalSpeed = 0.0)
        }
        
        _obstacles.value = _obstacles.value + obs
    }

    private fun checkCollisions() {
        val p = _player.value
        val centerX = width / 2
        val centerY = height * 0.8
        
        val balls = listOf(
            Pair(centerX + cos(p.angle) * p.radius, centerY + sin(p.angle) * p.radius),
            Pair(centerX + cos(p.angle + Math.PI) * p.radius, centerY + sin(p.angle + Math.PI) * p.radius)
        )
        
        for (obs in _obstacles.value) {
            var didCollide = false
            
            if (obs.type == ObstacleType.ROTATING || obs.type == ObstacleType.DIAGONAL) {
                val ox = obs.x + obs.width/2
                val oy = obs.y + obs.height/2
                
                for (ball in balls) {
                    val dx = ball.first - ox
                    val dy = ball.second - oy
                    
                    val localX = dx * cos(-obs.rotation) - dy * sin(-obs.rotation)
                    val localY = dx * sin(-obs.rotation) + dy * cos(-obs.rotation)
                    
                    val halfW = obs.width / 2
                    val halfH = obs.height / 2
                    
                    val closestX = max(-halfW, min(localX, halfW))
                    val closestY = max(-halfH, min(localY, halfH))
                    
                    val distX = localX - closestX
                    val distY = localY - closestY
                    
                    if ((distX*distX + distY*distY) < (p.ballRadius * p.ballRadius)) {
                        didCollide = true
                        break
                    }
                }
            } else {
                val obsMinX = obs.x
                val obsMaxX = obs.x + obs.width
                val obsMinY = obs.y
                val obsMaxY = obs.y + obs.height
                
                for (ball in balls) {
                    val closestX = max(obsMinX, min(ball.first, obsMaxX))
                    val closestY = max(obsMinY, min(ball.second, obsMaxY))
                    
                    val dx = ball.first - closestX
                    val dy = ball.second - closestY
                    
                    if ((dx*dx + dy*dy) < (p.ballRadius * p.ballRadius)) {
                        didCollide = true
                        break
                    }
                }
            }
            
            if (didCollide) {
                gameOver()
                return
            }
        }
    }
    
    private fun gameOver() {
        _state.value = GameState.GAMEOVER
        gameOverTimer = 0
        vibrateHeavy()
        
        consecutiveFailures++
        if (consecutiveFailures >= 5) {
            difficultyReduced = true
            obstaclesSinceFailure = 0
        }
        
        if (_score.value > _highScore.value) {
            _highScore.value = _score.value
            prefs.edit().putInt("highscore", _highScore.value).apply()
        }
    }
    
    private fun levelComplete() {
        _state.value = GameState.LEVEL_COMPLETE
        gameOverTimer = 0
        vibrateLight()
        
        consecutiveFailures = 0
        difficultyReduced = false
        
        if (_currentLevelIndex.value + 1 < levels.size) {
            val nextLevelId = _currentLevelIndex.value + 2
            if (nextLevelId > _unlockedLevel.value) {
                _unlockedLevel.value = nextLevelId
                prefs.edit().putInt("unlocked_level", nextLevelId).apply()
            }
        }
    }
    
    private fun vibrateLight() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(20, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            vibrator.vibrate(20)
        }
    }

    private fun vibrateHeavy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator.vibrate(VibrationEffect.createOneShot(50, VibrationEffect.DEFAULT_AMPLITUDE))
        } else {
            vibrator.vibrate(50)
        }
    }
    
    fun setStateLevelSelect() {
        _state.value = GameState.LEVEL_SELECT
    }
    
    fun setStateMenu() {
        _state.value = GameState.MENU
    }
}
