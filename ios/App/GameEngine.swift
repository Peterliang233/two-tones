import Foundation
import SwiftUI
import AVFoundation
import UIKit

enum GameState {
    case menu
    case levelSelect
    case playing
    case gameover
    case levelComplete
}

struct Level {
    let id: Int
    let name: String
    let targetScore: Int? // nil for endless
    let baseSpeed: Double
    let spawnInterval: Double
    let allowedTypes: [Obstacle.ObstacleType]
    let widthRatio: Double
    let color: UInt
}

struct Player {
    var angle: Double = 0
    // Make radius dynamic based on screen width
    // We'll store a "base" ratio or calculate it in update
    // But struct is value type. Let's keep it simple:
    // Engine will update these values when dimensions change.
    var radius: Double = 55
    var ballRadius: Double = 12
    let rotationSpeed: Double = 0.08
    
    mutating func update(left: Bool, right: Bool) {
        if left { angle -= rotationSpeed }
        if right { angle += rotationSpeed }
    }
}

struct Obstacle: Identifiable {
    let id = UUID()
    var x: Double
    var y: Double
    var width: Double // Changed to var to allow modification after init if needed
    var height: Double = 20
    var speed: Double
    
    // Dynamic behavior
    var type: ObstacleType = .rectangle
    var shapeParams: [String: Double] = [:]
    var isSplit: Bool = false
    var splitOffset: Double = 0
    var rotation: Double = 0
    var rotationalSpeed: Double = 0 // Added for static/dynamic rotation
    
    enum ObstacleType {
        case rectangle
        case lShapeLeft
        case lShapeRight
        case cross
        case variableSpeed
        case split
        case rotating
        case vertical // New type
        case diagonal // New type
    }
}

class GameEngine: ObservableObject {
    @Published var state: GameState = .menu
    @Published var score: Int = 0
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "twotones_highscore")
    @Published var unlockedLevel: Int = UserDefaults.standard.integer(forKey: "twotones_unlocked_level")
    @Published var currentLevelIndex: Int = 0
    
    // Level Definitions
    let levels: [Level] = [
        Level(id: 1, name: "Level 1", targetScore: 200, baseSpeed: 4.0, spawnInterval: 100, allowedTypes: [.rectangle, .vertical, .rotating], widthRatio: 0.6, color: 0x1a1a1a),
        Level(id: 2, name: "Level 2", targetScore: 400, baseSpeed: 3.5, spawnInterval: 90, allowedTypes: [.rectangle, .vertical, .rotating, .diagonal, .lShapeLeft, .lShapeRight], widthRatio: 0.5, color: 0x2a1a1a),
        Level(id: 3, name: "Level 3", targetScore: 600, baseSpeed: 3.0, spawnInterval: 80, allowedTypes: [.rectangle, .vertical, .diagonal, .cross, .rotating, .variableSpeed], widthRatio: 0.45, color: 0x1a2a1a),
        Level(id: 4, name: "Endless", targetScore: nil, baseSpeed: 2.5, spawnInterval: 70, allowedTypes: [.rectangle, .vertical, .diagonal, .cross, .rotating, .variableSpeed, .split], widthRatio: 0.4, color: 0x000000)
    ]
    
    // Game Entities
    @Published var player = Player()
    @Published var obstacles: [Obstacle] = []
    
    // Difficulty & Logic
    private var lastSafeZoneX: Double?
    private var consecutiveSafeZoneCount: Int = 0
    private var consecutiveFailures: Int = 0
    private var difficultyReduced: Bool = false
    private var obstaclesSinceFailure: Int = 0
    
    // Special Mechanics
    var emergencySpinsAvailable: Int = 1
    var scoreMultiplier: Int = 1
    var multiplierTimer: Int = 0 // Count obstacles
    
    // Input
    var inputLeft = false
    var inputRight = false
    
    // Internal
    private var gameLoop: Timer?
    private var spawnTimer = 0
    private var spawnInterval = 100.0
    private var baseSpeed = 2.0
    var width: Double = 0
    var height: Double = 0
    var gameOverTimer = 0
    
    // Audio & Haptics
    private var bgmPlayer: AVAudioPlayer?
    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    
    // Enum Definition moved outside or kept here if needed, but since we used it in struct Level, it should be accessible.
    // Let's make SpawnPattern public or internal enum inside GameEngine for better access
    enum SpawnPattern {
        case leftBlock
        case rightBlock
        case centerBlock
        case movingGap // Two blocks moving horizontally, creating a moving gap
        case rotor // Rotating bar
    }

    init() {
        if unlockedLevel == 0 { unlockedLevel = 1 } // Default to level 1
        setupAudio()
        setupLifecycleObservers()
        startGameLoop()
    }
    
    deinit {
        stopGameLoop()
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupLifecycleObservers() {
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.pauseGame()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resumeGame()
        }
    }
    
    func pauseGame() {
        stopGameLoop()
        bgmPlayer?.pause()
    }
    
    func resumeGame() {
        // Only resume loop if state is playing or similar dynamic state
        if state == .playing {
            startGameLoop()
            bgmPlayer?.play()
        }
    }
    
    func startGameLoop() {
        stopGameLoop()
        gameLoop = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            self?.update()
        }
    }
    
    func stopGameLoop() {
        gameLoop?.invalidate()
        gameLoop = nil
    }

    private func setupAudio() {
        // Try to load from main bundle first, then public folder
        guard let url = Bundle.main.url(forResource: "bgm", withExtension: "mp3", subdirectory: "public") else {
            print("BGM not found")
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            
            bgmPlayer = try AVAudioPlayer(contentsOf: url)
            bgmPlayer?.numberOfLoops = -1 // Infinite loop
            bgmPlayer?.volume = 0.5
            bgmPlayer?.prepareToPlay()
        } catch {
            print("Audio error: \(error)")
        }
    }
    
    func setDimensions(width: Double, height: Double) {
        self.width = width
        self.height = height
        
        // Dynamic Sizing Logic
        // Base ratios on iPhone 8 screen (375pt width)
        let scaleFactor = width / 375.0
        
        // Update Player
        // Base radius 55 -> Scaled
        player.radius = 55.0 * scaleFactor
        // Base ball radius 12 -> Scaled
        player.ballRadius = 12.0 * scaleFactor
    }
    
    func handleInput(left: Bool, right: Bool) {
        let changed = (left != inputLeft) || (right != inputRight)
        inputLeft = left
        inputRight = right
        
        if state == .menu {
            // Handled in View now
        } else if state == .levelSelect {
             // Handled in View
        } else if state == .gameover {
            if gameOverTimer > 10 && (left || right) {
                reset(levelIndex: currentLevelIndex)
            }
        } else if state == .levelComplete {
            if left || right {
                // Next level
                if currentLevelIndex + 1 < levels.count {
                    startLevel(index: currentLevelIndex + 1)
                } else {
                    // Back to menu if finished all levels
                    state = .menu
                }
            }
        } else if state == .playing {
            if changed && (left || right) {
                lightImpact.impactOccurred()
            }
        }
    }
    
    // Emergency Spin (Logic removed, kept for compatibility if needed)
    func triggerEmergencySpin() {
        // No-op
    }
    
    func quitGame() {
        stopGameLoop()
        state = .menu
        obstacles.removeAll()
        // Ensure inputs are reset so next game starts clean
        inputLeft = false
        inputRight = false
    }
    
    func startLevel(index: Int) {
        // Ensure loop is stopped before starting new one (though reset calls it, be safe)
        stopGameLoop()
        currentLevelIndex = index
        reset(levelIndex: index)
        // Explicitly start loop here if reset doesn't guarantee it (reset calls startGameLoop via bgmPlayer? No, it calls it directly?)
        // Wait, reset() calls `bgmPlayer?.play()`. It does NOT call `startGameLoop()`.
        // Let's check `reset` implementation.
        // `reset` sets state=.playing but does NOT call `startGameLoop()`.
        // `startGameLoop` is called in `init` and `resumeGame`.
        // We MUST call `startGameLoop()` when starting a level!
        startGameLoop()
    }
    
    func update() {
        if state == .gameover || state == .levelComplete {
            gameOverTimer += 1
            return
        }
        
        if state != .playing { return }
        
        // Update Multiplier Timer
        // Note: Logic says "Next 3 obstacles". 
        // We can decrement this counter on spawn or pass.
        // Let's implement score bonus logic in `score += 1`.
        
        // Check Level Complete
        let level = levels[currentLevelIndex]
        if let target = level.targetScore, score >= target {
            levelComplete()
            return
        }
        
        // Update Player
        player.update(left: inputLeft, right: inputRight)
        
        // Spawn Obstacles
        if width > 0 {
            spawnTimer += 1
            if Double(spawnTimer) > spawnInterval {
                spawnObstacle()
                spawnTimer = 0
                
                // Difficulty scaling within level (optional, but keep it mild)
                if spawnInterval > 40 { spawnInterval -= 0.05 }
                // Base speed is constant per level now, but maybe slight increase?
                // if baseSpeed < 8 { baseSpeed += 0.001 } 
            }
        }
        
        // Update Obstacles
        for i in obstacles.indices {
            // Variable Speed Logic
            if obstacles[i].type == .variableSpeed {
                // First half slow, second half fast
                if obstacles[i].y > height / 2 {
                    obstacles[i].speed = (height / (1.0 * 60)) // Fast
                } else {
                    obstacles[i].speed = (height / (2.0 * 60)) // Slow
                }
            }
            
            obstacles[i].y += obstacles[i].speed
            
            // Split Logic
            if obstacles[i].type == .split && !obstacles[i].isSplit {
                if obstacles[i].y > height / 2 {
                    // Trigger Split: This requires mutating the array, which is hard inside loop.
                    // Simplified: Just shift x?
                    // "Split into 2 short rectangles".
                    // Let's just shift it for now to simulate "divergence".
                    obstacles[i].x += obstacles[i].splitOffset
                    obstacles[i].isSplit = true
                }
            }
            
            // Handle dynamic types
            if obstacles[i].type == .rotating {
                 obstacles[i].rotation += 0.05
            } else if obstacles[i].type == .lShapeLeft || obstacles[i].type == .lShapeRight {
                // Logic mostly visual, collision handles rect
            }
        }
        
        // Cleanup & Scoring
        // We need to count passed obstacles for score multiplier logic
        // "Every 10 obstacles, trigger 2x score for next 3".
        // Instead of raw score += 1, let's track "obstacles passed".
        
        var passedCount = 0
        obstacles.removeAll { obs in
            if obs.y > height + 100 {
                passedCount += 1
                return true
            }
            return false
        }
        
        if passedCount > 0 {
            // Score Logic
            let basePoints = 1
            score += basePoints * scoreMultiplier
            
            // Track for multiplier trigger
            // Note: User said "Every 10 points" or "Every 10 obstacles"?
            // "每累计避障10个". So it's obstacle count based.
            // But we track `score`. Let's add `obstaclesPassedTotal`?
            // Or just use score % 10 == 0 if base is 1.
            if score % 10 == 0 {
                scoreMultiplier = 2
                multiplierTimer = 3 // Lasts for 3 obstacles
            } else if multiplierTimer > 0 {
                multiplierTimer -= passedCount
                if multiplierTimer <= 0 {
                    scoreMultiplier = 1
                    multiplierTimer = 0
                }
            }
            
            // Difficulty Restoration check
            if difficultyReduced {
                obstaclesSinceFailure += passedCount
                if obstaclesSinceFailure >= 3 {
                    difficultyReduced = false
                    obstaclesSinceFailure = 0
                }
            }
        }
        
        // Collision
        checkCollisions()
    }
    
    private func spawnObstacle() {
        let playerDiameter = player.radius * 2 + player.ballRadius * 2 + 20 // 20 safety margin
        let minSafeZone = playerDiameter
        
        // 1. Get Current Level Parameters
        // Ensure we use the configuration from the active level
        let level = levels[currentLevelIndex]
        
        var obstacleWidthRatio: Double = level.widthRatio
        var baseSpeedRatio: Double = level.baseSpeed // Duration (Seconds) to cross screen
        var allowedTypes: [Obstacle.ObstacleType] = level.allowedTypes
        var safeZoneRatio: Double = 0.4
        
        // Adaptive Difficulty Adjustment (Keep this, but make it relative to level base)
        if difficultyReduced {
            obstacleWidthRatio += 0.05
            baseSpeedRatio += 0.5 // Slower
            safeZoneRatio += 0.1
        } else {
            // Progressive difficulty WITHIN the level based on score
            // As you progress in the level, it gets slightly harder
            // E.g. every 50 points, speed up slightly?
            // Let's keep it simple: Use Level params as baseline.
            // But for Endless, we want ramping.
            if level.name == "Endless" {
                // Ramping logic for endless
                let ramping = min(Double(score) / 500.0, 1.0) // Cap at 500 points
                obstacleWidthRatio -= ramping * 0.1
                baseSpeedRatio -= ramping * 1.0 // Faster
            }
        }
        
        // Select Type FIRST
        let type = allowedTypes.randomElement()!
        
        // 2. Calculate Dimensions based on Type
        let margin: Double = 25.0
        let playableWidth = width - (2 * margin)
        let obsSpeed = height / (baseSpeedRatio * 60)
        
        // Default Dimensions
        var targetObsWidth = width * obstacleWidthRatio
        var obsHeight = max(15.0, height * 0.03)
        
        // Override for specific types
        if type == .vertical {
            // Vertical bar: Thin width, tall height
            targetObsWidth = 30.0 // Fixed thin width
            obsHeight = height * 0.25 // 25% screen height
        } else if type == .diagonal {
            // Diagonal bar: Long width, thin height (but rotated)
            // Effectively similar to rectangle but will be rotated.
            // Width should be somewhat long to cover space.
            targetObsWidth = width * 0.4
            obsHeight = 20.0
        }
        
        // Ensure Safe Zone Validity
        // Max allowed width logic
        let maxAllowedObsWidth = max(50.0, playableWidth - minSafeZone)
        let obsWidth = min(targetObsWidth, maxAllowedObsWidth)
        
        // 3. Safe Position Generation
        let maxObsX = width - obsWidth
        var x: Double = 0
        
        // Safe Zone Logic
        let safeZoneWidth = width * safeZoneRatio
        let actualSafeZoneWidth = max(safeZoneWidth, minSafeZone)
        
        // Pick Safe Zone
        let maxSafeX = width - actualSafeZoneWidth
        var safeZoneX: Double
        if maxSafeX > 0 {
            safeZoneX = Double.random(in: 0...maxSafeX)
        } else {
            safeZoneX = 0
        }
        
        // Check overlap logic (Simplified for brevity, logic preserved)
        if let last = lastSafeZoneX {
            let overlapStart = max(safeZoneX, last)
            let overlapEnd = min(safeZoneX + actualSafeZoneWidth, last + actualSafeZoneWidth)
            if overlapEnd > overlapStart { consecutiveSafeZoneCount += 1 } 
            else { consecutiveSafeZoneCount = 0 }
            
            if consecutiveSafeZoneCount >= 3 {
                if last < width / 2 {
                     let minX = width / 2
                     let maxX = width - actualSafeZoneWidth
                     if maxX > minX { safeZoneX = Double.random(in: minX...maxX) } else { safeZoneX = minX }
                } else {
                     let minX = 0.0
                     let maxX = width / 2 - actualSafeZoneWidth
                     if maxX > minX { safeZoneX = Double.random(in: minX...maxX) } else { safeZoneX = minX }
                }
                consecutiveSafeZoneCount = 0
            }
        }
        lastSafeZoneX = safeZoneX
        
        // Place Obstacle
        let placeLeft = Bool.random()
        if placeLeft {
            x = safeZoneX - obsWidth
            if x < margin {
                x = margin
                if x + obsWidth > safeZoneX { x = safeZoneX + actualSafeZoneWidth }
            }
        } else {
             x = safeZoneX + actualSafeZoneWidth
        }
        
        // Final Clamp
        if x < margin { x = margin }
        if x + obsWidth > width - margin { x = width - obsWidth - margin }
        
        // Create Obstacle
        var obstacle = Obstacle(x: x, y: -100, width: obsWidth, height: obsHeight, speed: obsSpeed, type: type)
        
        // Configure Type Specifics
        if type == .variableSpeed {
            // Logic handled in update
        } else if type == .split {
            obstacle.isSplit = true
            obstacle.splitOffset = Double.random(in: -20...20)
        } else if type == .rotating {
            obstacle.rotationalSpeed = 0.05
            obstacle.rotation = Double.random(in: 0...Double.pi)
        } else if type == .diagonal {
            // Static rotation (e.g., 45 degrees)
            // Randomly tilt left or right
            obstacle.rotation = Bool.random() ? .pi / 4 : -.pi / 4
            obstacle.rotationalSpeed = 0 // Static
        }
        
        obstacles.append(obstacle)
    }
    
    private func checkCollisions() {
        let centerX = width / 2
        let centerY = height * 0.8
        
        let balls = [
            CGPoint(x: centerX + cos(player.angle) * player.radius, y: centerY + sin(player.angle) * player.radius),
            CGPoint(x: centerX + cos(player.angle + .pi) * player.radius, y: centerY + sin(player.angle + .pi) * player.radius)
        ]
        
        for obs in obstacles {
            // Check collision
            var didCollide = false
            
            if obs.type == .rotating {
                // For rotating obstacles, we can rotate the ball point into the obstacle's local coordinate space
                // Obstacle center
                let ox = obs.x + obs.width/2
                let oy = obs.y + obs.height/2
                
                for ball in balls {
                    // Vector from obstacle center to ball
                    let dx = ball.x - ox
                    let dy = ball.y - oy
                    
                    // Rotate backwards by obstacle rotation
                    let localX = dx * cos(-obs.rotation) - dy * sin(-obs.rotation)
                    let localY = dx * sin(-obs.rotation) + dy * cos(-obs.rotation)
                    
                    // Check against unrotated rectangle centered at 0,0
                    let halfW = obs.width / 2
                    let halfH = obs.height / 2
                    
                    let closestX = max(-halfW, min(localX, halfW))
                    let closestY = max(-halfH, min(localY, halfH))
                    
                    let distX = localX - closestX
                    let distY = localY - closestY
                    
                    if (distX*distX + distY*distY) < (player.ballRadius * player.ballRadius) {
                        didCollide = true
                        break
                    }
                }
            } else {
                // Standard AABB check
                let obsRect = CGRect(x: obs.x, y: obs.y, width: obs.width, height: obs.height)
                
                for ball in balls {
                    let closestX = max(obsRect.minX, min(ball.x, obsRect.maxX))
                    let closestY = max(obsRect.minY, min(ball.y, obsRect.maxY))
                    
                    let dx = ball.x - closestX
                    let dy = ball.y - closestY
                    
                    if (dx*dx + dy*dy) < (player.ballRadius * player.ballRadius) {
                        didCollide = true
                        break
                    }
                }
            }
            
            if didCollide {
                gameOver()
                return
            }
        }
    }
    
    private func gameOver() {
        state = .gameover
        gameOverTimer = 0
        heavyImpact.impactOccurred()
        
        // Consecutive failure check
        consecutiveFailures += 1
        if consecutiveFailures >= 5 {
            difficultyReduced = true
            obstaclesSinceFailure = 0
        }
        
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "twotones_highscore")
        }
    }
    
    private func levelComplete() {
        state = .levelComplete
        gameOverTimer = 0
        lightImpact.impactOccurred()
        
        // Reset failures on success
        consecutiveFailures = 0
        difficultyReduced = false
        
        // Unlock next level
        if currentLevelIndex + 1 < levels.count {
            let nextLevelIndex = currentLevelIndex + 2 // 1-based ID
            if nextLevelIndex > unlockedLevel {
                unlockedLevel = nextLevelIndex
                UserDefaults.standard.set(unlockedLevel, forKey: "twotones_unlocked_level")
            }
        }
    }
    
    private func reset(levelIndex: Int = 0) {
        state = .playing
        score = 0
        obstacles.removeAll()
        player.angle = 0
        spawnTimer = 0
        
        // Logic Reset
        lastSafeZoneX = nil
        consecutiveSafeZoneCount = 0
        scoreMultiplier = 1
        multiplierTimer = 0
        emergencySpinsAvailable = 1 
        
        // Load Level Config
        // Ensure index is valid
        let safeIndex = min(max(0, levelIndex), levels.count - 1)
        currentLevelIndex = safeIndex
        
        let level = levels[safeIndex]
        spawnInterval = level.spawnInterval
        baseSpeed = level.baseSpeed
        
        inputLeft = false
        inputRight = false
        
        // Force dimensions if not set (avoid early spawn issues)
        if width == 0 { width = 300 } // Fallback until view updates
        if height == 0 { height = 600 }
        
        bgmPlayer?.play()
    }
}
