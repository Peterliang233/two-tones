import Foundation
import SwiftUI
import AVFoundation
import UIKit

enum GameState {
    case menu
    case playing
    case gameover
}

struct Player {
    var angle: Double = 0
    let radius: Double = 55
    let ballRadius: Double = 12
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
    let width: Double
    let height: Double = 30
    let speed: Double
    
    // Dynamic behavior
    var type: ObstacleType = .static
    var rotation: Double = 0 // In radians
    var moveSpeedX: Double = 0
    
    enum ObstacleType {
        case `static`
        case movingHorizontal
        case rotating
    }
}

class GameEngine: ObservableObject {
    @Published var state: GameState = .menu
    @Published var score: Int = 0
    @Published var highScore: Int = UserDefaults.standard.integer(forKey: "twotones_highscore")
    
    // Game Entities
    var player = Player()
    var obstacles: [Obstacle] = []
    
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
    
    init() {
        setupAudio()
        startGameLoop()
    }
    
    deinit {
        stopGameLoop()
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
    }
    
    func handleInput(left: Bool, right: Bool) {
        let changed = (left != inputLeft) || (right != inputRight)
        inputLeft = left
        inputRight = right
        
        if state == .menu {
            if left || right {
                reset()
            }
        } else if state == .gameover {
            if gameOverTimer > 10 && (left || right) {
                reset()
            }
        } else if state == .playing {
            if changed && (left || right) {
                lightImpact.impactOccurred()
            }
        }
    }
    
    func update() {
        if state == .gameover {
            gameOverTimer += 1
            return
        }
        
        if state != .playing { return }
        
        // Update Player
        player.update(left: inputLeft, right: inputRight)
        
        // Spawn Obstacles
        if width > 0 {
            spawnTimer += 1
            if Double(spawnTimer) > spawnInterval {
                spawnObstacle()
                spawnTimer = 0
                
                if spawnInterval > 40 { spawnInterval -= 0.05 }
                if baseSpeed < 8 { baseSpeed += 0.001 }
            }
        }
        
        // Update Obstacles
        for i in obstacles.indices {
            obstacles[i].y += obstacles[i].speed
            
            // Handle dynamic types
            if obstacles[i].type == .movingHorizontal {
                obstacles[i].x += obstacles[i].moveSpeedX
                // Bounce off walls
                if obstacles[i].x <= 0 || obstacles[i].x + obstacles[i].width >= width {
                    obstacles[i].moveSpeedX *= -1
                }
            } else if obstacles[i].type == .rotating {
                obstacles[i].rotation += 0.05
            }
        }
        
        // Cleanup
        obstacles.removeAll { $0.y > height + 100 }
        
        // Collision
        checkCollisions()
        
        // Score
        score += 1
    }
    
    private func spawnObstacle() {
        let centerX = width / 2
        let safeMargin: Double = 25 // Center clearance needed for vertical pass
        let wingClearance: Double = 10 // Extra space for horizontal pass
        
        // Define spawn patterns
        enum SpawnPattern {
            case leftBlock
            case rightBlock
            case centerBlock
            case movingGap // Two blocks moving horizontally, creating a moving gap
            case rotor // Rotating bar in center
        }
        
        // Progressive difficulty: Unlock patterns based on score
        var patterns: [SpawnPattern] = [.leftBlock, .rightBlock, .centerBlock]
        if score > 500 { patterns.append(.movingGap) }
        if score > 1000 { patterns.append(.rotor) }
        
        let pattern = patterns.randomElement()!
        
        var x: Double = 0
        var w: Double = 0
        
        switch pattern {
        case .leftBlock:
            let maxW = centerX - player.ballRadius - safeMargin
            let minW = 60.0
            if maxW < minW { w = minW } else { w = Double.random(in: minW...maxW) }
            x = 0
            obstacles.append(Obstacle(x: x, y: -100, width: w, speed: baseSpeed))
            
        case .rightBlock:
            let minX = centerX + player.ballRadius + safeMargin
            let maxW = width - minX
            let minW = 60.0
            if maxW < minW { w = minW } else { w = Double.random(in: minW...maxW) }
            x = width - w
            obstacles.append(Obstacle(x: x, y: -100, width: w, speed: baseSpeed))
            
        case .centerBlock:
            let maxW = 2.0 * (player.radius - player.ballRadius - wingClearance)
            let minW = 30.0
            w = Double.random(in: minW...max(minW, maxW))
            x = centerX - w / 2
            obstacles.append(Obstacle(x: x, y: -100, width: w, speed: baseSpeed))
            
        case .movingGap:
            // Spawn two blocks with a gap that moves left/right
            // Simplified: Spawn a single moving block that requires timing?
            // Let's spawn a "Gate" that slides horizontally.
            // A block that covers 60% of screen, moving back and forth.
            w = width * 0.6
            x = Double.random(in: 0...(width - w))
            var obs = Obstacle(x: x, y: -100, width: w, speed: baseSpeed)
            obs.type = .movingHorizontal
            obs.moveSpeedX = Double.random(in: 1...2) * (Bool.random() ? 1 : -1)
            obstacles.append(obs)
            
        case .rotor:
            // Rotating bar
            w = 120
            x = centerX - w / 2
            var obs = Obstacle(x: x, y: -100, width: w, speed: baseSpeed)
            obs.type = .rotating
            obstacles.append(obs)
        }
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
        
        if score > highScore {
            highScore = score
            UserDefaults.standard.set(highScore, forKey: "twotones_highscore")
        }
    }
    
    private func reset() {
        state = .playing
        score = 0
        obstacles.removeAll()
        player.angle = 0
        spawnTimer = 0
        spawnInterval = 100
        baseSpeed = 2
        inputLeft = false
        inputRight = false
        
        bgmPlayer?.play()
    }
}
