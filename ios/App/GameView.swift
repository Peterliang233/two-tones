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
                        if obs.type == .rotating {
                            context.drawLayer { ctx in
                                ctx.translateBy(x: obs.x + obs.width/2, y: obs.y + obs.height/2)
                                ctx.rotate(by: .radians(obs.rotation))
                                let rect = CGRect(x: -obs.width/2, y: -obs.height/2, width: obs.width, height: obs.height)
                                ctx.fill(Path(rect), with: .color(.white))
                            }
                        } else {
                            let rect = CGRect(x: obs.x, y: obs.y, width: obs.width, height: obs.height)
                            context.fill(Path(rect), with: .color(.white))
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
            .overlay(uiOverlay)
            .overlay(inputLayer)
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
    
    var uiOverlay: some View {
        VStack {
            if engine.state == .menu {
                Spacer()
                Text("TWO TONES")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)
                Text("Tap Left/Right to Rotate")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
                    .padding(.top, 10)
                Text("Tap to Start")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .padding(.top, 40)
                if engine.highScore > 0 {
                    Text("Best: \(engine.highScore / 10)")
                        .foregroundColor(.yellow)
                        .padding(.top, 20)
                }
                Spacer()
            } else if engine.state == .playing {
                HStack {
                    Text("\(engine.score / 10)")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding()
                        .padding(.top, 40) // Status bar area
                    Spacer()
                }
                Spacer()
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
