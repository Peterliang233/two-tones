import SwiftUI

struct GameView: View {
    @StateObject private var engine = GameEngine()
    
    var body: some View {
        GeometryReader { geometry in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    // Swift requires us to be careful.
                    // Let's perform the update.
                    // We only set dimensions here if they changed, to avoid engine work in render loop
                    if engine.width != size.width || engine.height != size.height {
                        DispatchQueue.main.async {
                            engine.setDimensions(width: size.width, height: size.height)
                        }
                    }
                    
                    // Draw Background
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x1a1a1a)))
                    
                    // Draw Obstacles
                    for obs in engine.obstacles {
                        // Color based on speed? Or just white.
                        // Variable speed gets a tint?
                        var obsColor: Color = .white
                        if obs.type == .variableSpeed {
                            obsColor = .yellow
                        }
                        
                        if obs.type == .lShapeLeft {
                            // Draw L shape blocking Left side
                            // We treat (x,y) as top-left of bounding box
                            // L-Shape Left: |__
                            // Vertical bar on left, horizontal bar on bottom
                            let rect = CGRect(x: obs.x, y: obs.y, width: obs.width, height: obs.height)
                            context.fill(Path(rect), with: .color(obsColor))
                            // Add extra arm?
                            // Simplified: Just draw rect for now, L-shape logic in collision is "rect" anyway.
                            // If we want visual L, we need data.
                            // Let's stick to Rect for visual simplicity unless we want true L geometry.
                            // The user spec says "L Shape (Width=50%)".
                            // If it's just a visual shape, collision must match.
                            // Currently collision is AABB (Rect). So we draw Rect.
                        } else if obs.type == .cross {
                            // Cross shape +
                            let rectH = CGRect(x: obs.x, y: obs.y + obs.height/3, width: obs.width, height: obs.height/3)
                            let rectV = CGRect(x: obs.x + obs.width/2 - 15, y: obs.y, width: 30, height: obs.height)
                            context.fill(Path(rectH), with: .color(obsColor))
                            context.fill(Path(rectV), with: .color(obsColor))
                        } else if obs.type == .rotating || obs.type == .diagonal {
                            context.drawLayer { ctx in
                                ctx.translateBy(x: obs.x + obs.width/2, y: obs.y + obs.height/2)
                                ctx.rotate(by: .radians(obs.rotation))
                                let rect = CGRect(x: -obs.width/2, y: -obs.height/2, width: obs.width, height: obs.height)
                                ctx.fill(Path(rect), with: .color(obsColor))
                            }
                        } else {
                            // Rectangle / Vertical / Variable / Split
                            let rect = CGRect(x: obs.x, y: obs.y, width: obs.width, height: obs.height)
                            context.fill(Path(rect), with: .color(obsColor))
                        }
                    }
                    
                    // Draw Player (Only if playing/gameover)
                    if engine.state == .playing || engine.state == .gameover {
                        let centerX = size.width / 2
                        let centerY = size.height * 0.8
                        
                        // Ring
                        let ringRect = CGRect(x: centerX - engine.player.radius, y: centerY - engine.player.radius, width: engine.player.radius * 2, height: engine.player.radius * 2)
                        let ringPath = Path(ellipseIn: ringRect)
                        context.stroke(ringPath, with: .color(.white.opacity(0.1)), lineWidth: 2)
                        
                        // Balls
                        let p = engine.player
                        let x1 = centerX + cos(p.angle) * p.radius
                        let y1 = centerY + sin(p.angle) * p.radius
                        let x2 = centerX + cos(p.angle + .pi) * p.radius
                        let y2 = centerY + sin(p.angle + .pi) * p.radius
                        
                        let b1 = Path(ellipseIn: CGRect(x: x1 - p.ballRadius, y: y1 - p.ballRadius, width: p.ballRadius*2, height: p.ballRadius*2))
                        context.fill(b1, with: .color(Color(hex: 0xff3b30))) // Red
                        
                        let b2 = Path(ellipseIn: CGRect(x: x2 - p.ballRadius, y: y2 - p.ballRadius, width: p.ballRadius*2, height: p.ballRadius*2))
                        context.fill(b2, with: .color(Color(hex: 0x007aff))) // Blue
                    }
                }
            }
            .overlay(inputLayer) // Moved inputLayer BEHIND uiOverlay (Wait, overlay stacks on top. So inputLayer is on TOP of TimelineView)
            .overlay(uiOverlay) // uiOverlay is on TOP of inputLayer
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
    
    var uiOverlay: some View {
        VStack {
            if engine.state == .menu {
                Spacer()
                
                // Logo Icon
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 4)
                        .frame(width: 80, height: 80)
                    
                    Circle()
                        .fill(Color(hex: 0xff3b30)) // Red ball
                        .frame(width: 20, height: 20)
                        .offset(x: 40)
                    
                    Circle()
                        .fill(Color(hex: 0x007aff)) // Blue ball
                        .frame(width: 20, height: 20)
                        .offset(x: -40)
                }
                .rotationEffect(.degrees(-45)) // Stylistic tilt
                .padding(.bottom, 20)
                
                Text("TWO TONES")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
                
                Button(action: {
                    engine.startLevel(index: 0) // Start Level 1
                }) {
                    Text("PLAY")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 200, height: 60)
                        .background(Color.white)
                        .cornerRadius(30)
                }
                .padding(.top, 40)
                
                Button(action: {
                    engine.state = .levelSelect
                }) {
                    Text("LEVELS")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 200, height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(Color.white, lineWidth: 2)
                        )
                }
                .padding(.top, 20)

                Spacer()
            } else if engine.state == .levelSelect {
                VStack {
                    Text("SELECT LEVEL")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.top, 60)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
                            ForEach(engine.levels, id: \.id) { level in
                                let isLocked = level.id > engine.unlockedLevel
                                Button(action: {
                                    if !isLocked {
                                        engine.startLevel(index: level.id - 1)
                                    }
                                }) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(isLocked ? Color.gray.opacity(0.3) : Color.white.opacity(0.2))
                                            .frame(height: 100)
                                        
                                        if isLocked {
                                            Image(systemName: "lock.fill")
                                                .font(.title)
                                                .foregroundColor(.gray)
                                        } else {
                                            VStack {
                                                Text("\(level.id)")
                                                    .font(.system(size: 40, weight: .bold))
                                                    .foregroundColor(.white)
                                                Text(level.name)
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                            }
                                        }
                                    }
                                }
                                .disabled(isLocked)
                            }
                        }
                        .padding()
                    }
                    
                    Button(action: {
                        engine.state = .menu
                    }) {
                        Text("BACK")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                .background(Color.black.opacity(0.9))
            } else if engine.state == .playing {
                HStack(alignment: .top) {
                    // Home Button
                    Button(action: {
                        withAnimation {
                            engine.quitGame()
                        }
                    }) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.6))
                            .padding(8)
                            .background(Color.black.opacity(0.3))
                            .clipShape(Circle())
                    }
                    .padding(.top, 40)
                    .padding(.leading, 16)
                    
                    VStack(alignment: .leading) {
                        Text(engine.levels[engine.currentLevelIndex].name)
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(engine.score / 10)")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40) // Status bar area
                    .padding(.leading, 8)
                    
                    Spacer()
                    
                    if let target = engine.levels[engine.currentLevelIndex].targetScore {
                        VStack(alignment: .trailing) {
                            Text("Target")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text("\(target / 10)")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .padding()
                        .padding(.top, 40)
                    }
                    if engine.scoreMultiplier > 1 {
                        Text("2x SCORE!")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.top, 80)
                            .transition(.scale)
                    }
                    
                    if engine.emergencySpinsAvailable > 0 {
                        // Removed
                    }
                }
                Spacer()
            } else if engine.state == .levelComplete {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Text("LEVEL COMPLETE")
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(.yellow)
                            Text("Score: \(engine.score / 10)")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(.top, 10)
                            
                            Text("Tap for Next Level")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(.top, 40)
                                .opacity(engine.gameOverTimer % 60 < 30 ? 1 : 0.5) // Blink effect
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        engine.handleInput(left: true, right: false)
                    }
            } else if engine.state == .gameover {
                Color.black.opacity(0.8)
                    .edgesIgnoringSafeArea(.all)
                    .overlay(
                        VStack {
                            Text("GAME OVER")
                                .font(.system(size: 40, weight: .bold))
                                .foregroundColor(.white)
                            Text("Score: \(engine.score / 10)")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(.top, 10)
                            if engine.highScore > 0 {
                                Text("Best: \(engine.highScore / 10)")
                                    .font(.system(size: 16))
                                    .foregroundColor(.yellow)
                                    .padding(.top, 10)
                            }
                            Text("Tap to Restart")
                                .font(.system(size: 16))
                                .foregroundColor(engine.gameOverTimer > 10 ? .white : .gray)
                                .padding(.top, 40)
                        }
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        engine.handleInput(left: true, right: false)
                    }
            }
        }
    }
    
    var inputLayer: some View {
        HStack(spacing: 0) {
            // Left Zone
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in engine.handleInput(left: true, right: engine.inputRight) }
                        .onEnded { _ in engine.handleInput(left: false, right: engine.inputRight) }
                )
            
            // Right Zone
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in engine.handleInput(left: engine.inputLeft, right: true) }
                        .onEnded { _ in engine.handleInput(left: engine.inputLeft, right: false) }
                )
        }
    }
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 08) & 0xff) / 255,
            blue: Double((hex >> 00) & 0xff) / 255,
            opacity: alpha
        )
    }
}
