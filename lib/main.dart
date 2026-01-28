import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: 'AIzaSyBXlM_064P6R_XiBlDDTtv3KO5tXuFNO2g',
      appId: '1:962882491474:web:0886f14d9fb37622df3b8b',
      messagingSenderId: '962882491474',
      projectId: 'udd-bulbul-pinaka',
      authDomain: 'udd-bulbul-pinaka.firebaseapp.com',
      storageBucket: 'udd-bulbul-pinaka.firebasestorage.app',
    ),
  );
  runApp(const UddBulbulUddApp());
}

class UddBulbulUddApp extends StatelessWidget {
  const UddBulbulUddApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Udd Bulbul Udd',
      theme: ThemeData(
        fontFamily: 'Segoe UI',
      ),
      home: const GameScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late GameEngine gameEngine;
  late Ticker _ticker;
  double _lastTime = 0;

  @override
  void initState() {
    super.initState();
    gameEngine = GameEngine(onGameStateChange: () {
      if (mounted) setState(() {}); // Only needed for UI overlay updates, not painting
    });
    
    _ticker = createTicker((Duration elapsed) {
      final double currentTime = elapsed.inMilliseconds.toDouble(); 
      final double dt = _lastTime == 0 ? 0 : (currentTime - _lastTime) / 1000.0;
      _lastTime = currentTime;
      
      gameEngine.update(dt);
      gameEngine.notifier.value++; // Trigger repaint
    });

    // Start loading high score
    gameEngine.loadHighScore();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (gameEngine.gameState == GameState.menu || gameEngine.gameState == GameState.gameOver) {
      gameEngine.reset();
      gameEngine.gameState = GameState.playing;
      _lastTime = 0;
      _ticker.start();
    } else if (gameEngine.gameState == GameState.playing) {
      gameEngine.jump();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTapDown: (_) => _handleTap(),
        child: Stack(
          children: [
            // The Game Canvas (Repaints on every tick via ListenableBuilder)
            SizedBox.expand(
              child: CustomPaint(
                painter: GamePainter(gameEngine: gameEngine, repaint: gameEngine.notifier),
              ),
            ),
            
            // Stats / UI Overlay (Only rebuilds on score/state change)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Score: ${gameEngine.score}', 
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                        Text('High: ${gameEngine.highScore}', 
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Menu Overlay
            if (gameEngine.gameState == GameState.menu)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20),
                    boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)]
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                       Text("Udd Bulbul Udd", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                       SizedBox(height: 10),
                       Text("Tap to Fly!", style: TextStyle(fontSize: 24)),
                    ],
                  ),
                ),
              ),

            // Game Over Overlay
            if (gameEngine.gameState == GameState.gameOver)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(30),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(20),
                    boxShadow: [const BoxShadow(color: Colors.black26, blurRadius: 10)]
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       const Text("Game Over", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.red)),
                       Text("Score: ${gameEngine.score}", style: const TextStyle(fontSize: 28)),
                       const SizedBox(height: 20),
                       const Text("Tap to Restart", style: TextStyle(fontSize: 20)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum GameState { menu, playing, gameOver }

class GameEngine {
  final ValueNotifier<int> notifier = ValueNotifier(0);
  final VoidCallback onGameStateChange;

  GameState gameState = GameState.menu;
  double birdY = 0;
  double birdVelocity = 0;
  double birdRotation = 0;
  int score = 0;
  int highScore = 0;
  
  // Parallax & Animation State
  double backgroundOffset = 0; // For distant scenery (Taj Mahal)
  double groundOffset = 0;     // For ground texture scrolling
  double gameTime = 0;         // Accumulator for animations
  List<Cloud> clouds = [];

  // Game Constants
  static const double gravity = 1200.0;
  static const double jumpForce = -400.0;
  static const double birdSize = 40.0; // Radius approx
  static const double birdX = -50.0;   // Centered horizontally, 0 is center, so -50 is slightly left
  static const double pillarSpeed = 200.0;
  static const double pillarWidth = 60.0;
  static const double pillarGap = 160.0;

  List<Pillar> pillars = [];
  double timeSinceSpawn = 0;
  Size screenSize = Size.zero;

  GameEngine({required this.onGameStateChange});

  void reset() {
    birdY = 0;
    birdVelocity = 0;
    birdRotation = 0;
    score = 0;
    pillars.clear();
    clouds.clear();
    timeSinceSpawn = 0;
    gameTime = 0;
    backgroundOffset = 0;
    groundOffset = 0;
    _spawnPillar(initialOffset: 400);
    _spawnClouds();
  }

  void _spawnClouds() {
    for (int i = 0; i < 5; i++) {
      clouds.add(Cloud(
        x: (Random().nextDouble() * 800) - 400, // Spread across screen width assumption
        y: -300 + Random().nextDouble() * 200, // Top area
        speed: 10 + Random().nextDouble() * 20,
        scale: 0.8 + Random().nextDouble() * 0.4,
      ));
    }
  }

  void jump() {
    birdVelocity = jumpForce;
  }

  void update(double dt) {
    // Background Animations (Run even in menu if we wanted, but sticking to playing for now or always?)
    // Let's update animations always for visual flair if possible, but pillars only in playing.
    // For now, consistent with original logic, only update in playing.
    if (gameState != GameState.playing) return;
    if (dt > 0.1) dt = 0.1; // Cap dt to prevent huge jumps

    gameTime += dt;

    // Scroll Backgrounds (Parallax)
    // Ground moves at same speed as pillars relative to bird
    groundOffset += pillarSpeed * dt;
    // Taj Mahal / Scenery moves slower (e.g., 20% speed)
    backgroundOffset += (pillarSpeed * 0.2) * dt;

    // Cloud Animation
    for (var cloud in clouds) {
      cloud.x -= cloud.speed * dt;
      // Wrap clouds
      if (cloud.x < -(screenSize.width/2) - 100) {
        cloud.x = (screenSize.width/2) + 100;
        cloud.y = -300 + Random().nextDouble() * 200;
      }
    }

    // Physics
    birdVelocity += gravity * dt;
    birdY += birdVelocity * dt;
    
    // Rotation logic (tilts up when jumping, down when falling)
    birdRotation = (birdVelocity * 0.002).clamp(-0.5, 0.5);

    // Ground/Ceiling Collision (assuming screen height approx 800 for logic, but dynamic)
    final limit = (screenSize.height / 2) - 20;
    if (birdY > limit || birdY < -limit) {
      gameOver();
    }

    // Pillar Logic
    for (int i = pillars.length - 1; i >= 0; i--) {
      pillars[i].x -= pillarSpeed * dt;

      // Passing score
      if (!pillars[i].passed && pillars[i].x < birdX) {
        score++;
        pillars[i].passed = true;
        onGameStateChange(); // Update UI score
      }
      
      // Collision
      if (_checkCollision(pillars[i])) {
        gameOver();
      }

      // Cleanup
      if (pillars[i].x < -(screenSize.width/2) - 100) {
        pillars.removeAt(i);
      }
    }

    // Spawning
    if (pillars.isNotEmpty && pillars.last.x < (screenSize.width/2) - 250) {
      _spawnPillar();
    }
  }

  void _spawnPillar({double initialOffset = 0}) {
    final startX = (screenSize.width/2) + initialOffset;
    // Visible height range
    final availableH = screenSize.height * 0.6; 
    final minH = -availableH/2;
    final maxH = availableH/2;
    // Random height for the gap center
    final gapCenter = minH + Random().nextDouble() * (maxH - minH);
    
    pillars.add(Pillar(x: startX, gapCenter: gapCenter));
  }

  bool _checkCollision(Pillar p) {
    // Bird Hitbox (approx circle at birdX, birdY, radius 15)
    // Pillar Hitbox (Left/Right X, and Gap Top/Bottom)
    
    if (p.x < birdX + 15 && p.x + pillarWidth > birdX - 15) {
      // Horizontal overlap
      // Check vertical gap
      final gapTop = p.gapCenter - pillarGap / 2;
      final gapBottom = p.gapCenter + pillarGap / 2;
      
      if (birdY - 15 < gapTop || birdY + 15 > gapBottom) {
        return true;
      }
    }
    return false;
  }

  void gameOver() {
    gameState = GameState.gameOver;
    if (score > highScore) {
      highScore = score;
      _saveHighScore();
    }
    onGameStateChange();
  }

  Future<void> loadHighScore() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('highscores').doc('global_high_score').get();
      if (doc.exists) {
        highScore = (doc.data()?['score'] ?? 0) as int;
        onGameStateChange();
      }
    } catch (_) {}
  }

  Future<void> _saveHighScore() async {
    try {
      await FirebaseFirestore.instance.collection('highscores').doc('global_high_score').set({'score': highScore});
    } catch (_) {}
  }
}

class Pillar {
  double x;
  double gapCenter;
  bool passed;
  Pillar({required this.x, required this.gapCenter, this.passed = false});
}

class Cloud {
  double x;
  double y;
  double speed;
  double scale;
  Cloud({required this.x, required this.y, required this.speed, required this.scale});
}

class GamePainter extends CustomPainter {
  final GameEngine gameEngine;
  
  GamePainter({required this.gameEngine, required Listenable repaint}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    gameEngine.screenSize = size;
    final center = Offset(size.width / 2, size.height / 2);
    
    _drawSkyAndBackground(canvas, size);

    // Translate to center for easier game coordinates (0,0 is center)
    canvas.save();
    canvas.translate(center.dx, center.dy);

    _drawPillars(canvas);
    _drawBird(canvas);

    canvas.restore();
  }

  void _drawSkyAndBackground(Canvas canvas, Size size) {
    // 1. Sky Gradient
    final Rect rect = Offset.zero & size;
    final Paint skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF4FC3F7), Color(0xFFE1F5FE)], // Slightly more vibrant
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);

    // 2. Sun with Glow
    final sunPos = Offset(size.width * 0.85, 80);
    final paintSunGlow = Paint()..color = Colors.yellow.withOpacity(0.2);
    canvas.drawCircle(sunPos, 50 + sin(gameEngine.gameTime * 2) * 5, paintSunGlow); // Pulsing glow
    canvas.drawCircle(sunPos, 40, paintSunGlow);
    final paintSun = Paint()..color = const Color(0xFFFFEB3B);
    canvas.drawCircle(sunPos, 30, paintSun);

    // 3. Clouds (Parallax Layer 1 - Slowest? Actually clouds usually move separate from ground)
    // We already have cloud objects moving in GameEngine, just draw them.
    // We need to translate coordinates because clouds are stored as centered coordinates in engine
    // but here we are drawing in screen coordinates (0,0 top left).
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2); // Match engine coordinate system origin
    for (var cloud in gameEngine.clouds) {
      _drawCloud(canvas, cloud);
    }
    canvas.restore();

    // 4. Scenery / Taj Mahal (Parallax Layer 2)
    // We want this to scroll infinitely.
    final double sceneryWidth = size.width * 1.5; // Make scenery wider than screen to vary it
    if (sceneryWidth <= 0) return; // Safety
    
    final double scrollX = gameEngine.backgroundOffset % sceneryWidth;
    
    // Draw two copies to cover the screen
    canvas.save();
    canvas.translate(-scrollX, 0); // Move left
    _drawScenery(canvas, size, sceneryWidth);
    canvas.translate(sceneryWidth, 0); // Draw next tile
    _drawScenery(canvas, size, sceneryWidth);
    canvas.restore();

    // 5. Ground (Base) with Scrolling Texture
    final bottomY = size.height - 50;
    final groundRect = Rect.fromLTWH(0, bottomY, size.width, 50);
    final paintGround = Paint()..color = const Color(0xFFD7CCC8); // Base ground color
    canvas.drawRect(groundRect, paintGround);

    // Ground scrolling texture
    canvas.save();
    canvas.clipRect(groundRect);
    final paintGroundDetail = Paint()..color = const Color(0xFFBCAAA4)..strokeWidth = 2;
    // Diagonal lines
    final double groundScroll = gameEngine.groundOffset % 40;
    for (double i = -40; i < size.width + 40; i += 40) {
      // Draw lines moving left (so we subtract scroll)
      double x = i - groundScroll;
      canvas.drawLine(Offset(x, bottomY), Offset(x + 20, size.height), paintGroundDetail);
    }
    // Top border of ground
    canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), Paint()..color = const Color(0xFF8D6E63)..strokeWidth = 3);
    canvas.restore();
  }

  void _drawCloud(Canvas canvas, Cloud cloud) {
    canvas.save();
    canvas.translate(cloud.x, cloud.y);
    canvas.scale(cloud.scale);
    final paint = Paint()..color = Colors.white.withOpacity(0.7);
    // Fluffy cloud shape
    canvas.drawCircle(const Offset(0, 0), 30, paint);
    canvas.drawCircle(const Offset(-25, 10), 20, paint);
    canvas.drawCircle(const Offset(25, 10), 20, paint);
    canvas.drawCircle(const Offset(-15, -15), 25, paint);
    canvas.drawCircle(const Offset(15, -15), 25, paint);
    canvas.restore();
  }

  void _drawScenery(Canvas canvas, Size size, double width) {
    // Draw Taj Mahal centered in this "width" tile
    final bottomY = size.height - 50;
    final centerX = width / 2;

    final paintTaj = Paint()..color = const Color(0xFFF5F5F5); // White marble
    final paintShadow = Paint()..color = const Color(0xFFE0E0E0);
    final paintDark = Paint()..color = const Color(0xFFBDBDBD);

    // --- Main Platform ---
    canvas.drawRect(Rect.fromCenter(center: Offset(centerX, bottomY - 10), width: 350, height: 20), paintTaj);
    
    // --- Main Structure ---
    final rectMain = Rect.fromCenter(center: Offset(centerX, bottomY - 70), width: 160, height: 100);
    canvas.drawRect(rectMain, paintTaj);
    // Chamfered corners indication (shadows)
    canvas.drawRect(Rect.fromLTWH(rectMain.left, rectMain.top, 10, rectMain.height), paintShadow);
    canvas.drawRect(Rect.fromLTWH(rectMain.right - 10, rectMain.top, 10, rectMain.height), paintShadow);

    // --- Central Arch (Iwan) ---
    final archPath = Path()
      ..moveTo(centerX - 25, bottomY - 20)
      ..lineTo(centerX - 25, bottomY - 80)
      ..arcToPoint(Offset(centerX + 25, bottomY - 80), radius: const Radius.circular(25))
      ..lineTo(centerX + 25, bottomY - 20)
      ..close();
    canvas.drawPath(archPath, paintDark);

    // Smaller arches on sides
    void drawSideArch(double offset) {
      final p = Path()
        ..moveTo(centerX + offset - 10, bottomY - 40)
        ..lineTo(centerX + offset - 10, bottomY - 70)
        ..arcToPoint(Offset(centerX + offset + 10, bottomY - 70), radius: const Radius.circular(10))
        ..lineTo(centerX + offset + 10, bottomY - 40)
        ..close();
      canvas.drawPath(p, paintDark); // Lower
       final p2 = Path()
        ..moveTo(centerX + offset - 10, bottomY - 80)
        ..lineTo(centerX + offset - 10, bottomY - 100)
        ..arcToPoint(Offset(centerX + offset + 10, bottomY - 100), radius: const Radius.circular(10))
        ..lineTo(centerX + offset + 10, bottomY - 80)
        ..close();
      canvas.drawPath(p2, paintDark); // Upper
    }
    drawSideArch(-55);
    drawSideArch(55);

    // --- Central Dome ---
    final domePath = Path()
      ..moveTo(centerX - 45, bottomY - 120)
      ..cubicTo(
          centerX - 55, bottomY - 150, // ctrl1
          centerX - 30, bottomY - 200, // ctrl2
          centerX, bottomY - 210)      // end
      ..cubicTo(
          centerX + 30, bottomY - 200,
          centerX + 55, bottomY - 150,
          centerX + 45, bottomY - 120)
      ..close();
    canvas.drawPath(domePath, paintTaj);
    
    // Finial
    canvas.drawRect(Rect.fromCenter(center: Offset(centerX, bottomY - 210), width: 3, height: 25), Paint()..color = const Color(0xFFFFD700));

    // --- Side Domes (Chhatris) ---
    void drawChhatri(double dx) {
      // Pillars
      canvas.drawRect(Rect.fromLTWH(dx - 12, bottomY - 120, 4, 20), paintTaj);
      canvas.drawRect(Rect.fromLTWH(dx + 8, bottomY - 120, 4, 20), paintTaj);
      // Dome
      final d = Path()
        ..moveTo(dx - 15, bottomY - 120)
        ..quadraticBezierTo(dx, bottomY - 150, dx + 15, bottomY - 120)
        ..close();
      canvas.drawPath(d, paintTaj);
    }
    drawChhatri(centerX - 55);
    drawChhatri(centerX + 55);

    // --- Minarets ---
    void drawMinaret(double dx) {
       final minaretPath = Path()
        ..moveTo(dx - 6, bottomY)
        ..lineTo(dx - 4, bottomY - 160)
        ..lineTo(dx + 4, bottomY - 160)
        ..lineTo(dx + 6, bottomY)
        ..close();
       canvas.drawPath(minaretPath, paintTaj);
       // Balconies
       canvas.drawRect(Rect.fromCenter(center: Offset(dx, bottomY - 50), width: 14, height: 3), paintShadow);
       canvas.drawRect(Rect.fromCenter(center: Offset(dx, bottomY - 100), width: 12, height: 3), paintShadow);
       canvas.drawRect(Rect.fromCenter(center: Offset(dx, bottomY - 160), width: 10, height: 3), paintShadow);
       // Dome
       canvas.drawOval(Rect.fromCenter(center: Offset(dx, bottomY - 165), width: 10, height: 8), paintTaj);
    }
    drawMinaret(centerX - 140);
    drawMinaret(centerX + 140);
    drawMinaret(centerX - 90);
    drawMinaret(centerX + 90);

    // --- Distant Trees / Vegetation ---
    // Simple silhouette hills/trees in background
    final paintTree = Paint()..color = const Color(0xFF81C784).withOpacity(0.5);
    final treePath = Path();
    treePath.moveTo(0, bottomY);
    for(double i=0; i < width; i+= 40) {
      treePath.quadraticBezierTo(i + 20, bottomY - 30 - Random(i.toInt()).nextDouble()*20, i + 40, bottomY);
    }
    treePath.lineTo(width, bottomY);
    treePath.close();
    canvas.drawPath(treePath, paintTree);
  }

  void _drawPillars(Canvas canvas) {
    final paintPillar = Paint()..color = const Color(0xFF2E7D32); // Green marble/plants
    final paintHighlight = Paint()..color = Colors.white.withOpacity(0.1);
    final paintShadow = Paint()..color = Colors.black.withOpacity(0.1);
    final paintBorder = Paint()
      ..color = const Color(0xFF1B5E20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (var p in gameEngine.pillars) {
      final w = GameEngine.pillarWidth;
      final gapHalf = GameEngine.pillarGap / 2;
      
      void drawPillarRect(Rect r) {
        canvas.drawRect(r, paintPillar);
        // Highlight (Left side)
        canvas.drawRect(Rect.fromLTWH(r.left, r.top, 10, r.height), paintHighlight);
        // Shadow (Right side)
        canvas.drawRect(Rect.fromLTWH(r.right - 10, r.top, 10, r.height), paintShadow);
        canvas.drawRect(r, paintBorder);

        // Cap details
        canvas.drawRect(Rect.fromLTWH(r.left - 5, r.bottom - 20, w + 10, 20), paintPillar);
        canvas.drawRect(Rect.fromLTWH(r.left - 5, r.bottom - 20, w + 10, 20), paintBorder);
      }

      // Top Pillar
      // Note: We use -1000 for top, but for shading we need to be careful. Clip rect handles it mostly.
      final topRect = Rect.fromLTRB(p.x, -1000, p.x + w, p.gapCenter - gapHalf);

      canvas.save();
      canvas.clipRect(topRect); // Clip for gradient/shading
      canvas.drawRect(topRect, paintPillar);
      canvas.drawRect(Rect.fromLTWH(topRect.left, topRect.top, 10, topRect.height), paintHighlight);
      canvas.drawRect(Rect.fromLTWH(topRect.right - 10, topRect.top, 10, topRect.height), paintShadow);
      canvas.restore();
      canvas.drawRect(topRect, paintBorder);
      
      // Pillar Cap (Bottom of top pillar)
      final capHeight = 20.0;
      final topCapRect = Rect.fromLTRB(p.x - 5, (p.gapCenter - gapHalf) - capHeight, p.x + w + 5, p.gapCenter - gapHalf);
      canvas.drawRect(topCapRect, paintPillar);
      canvas.drawRect(topCapRect, paintBorder);

      // Bottom Pillar
      final bottomRect = Rect.fromLTRB(p.x, p.gapCenter + gapHalf, p.x + w, 1000);
      canvas.save();
      canvas.clipRect(bottomRect);
      canvas.drawRect(bottomRect, paintPillar);
      canvas.drawRect(Rect.fromLTWH(bottomRect.left, bottomRect.top, 10, bottomRect.height), paintHighlight);
      canvas.drawRect(Rect.fromLTWH(bottomRect.right - 10, bottomRect.top, 10, bottomRect.height), paintShadow);
      canvas.restore();
      canvas.drawRect(bottomRect, paintBorder);

      // Pillar Cap (Top of bottom pillar)
      final bottomCapRect = Rect.fromLTRB(p.x - 5, p.gapCenter + gapHalf, p.x + w + 5, p.gapCenter + gapHalf + capHeight);
      canvas.drawRect(bottomCapRect, paintPillar);
      canvas.drawRect(bottomCapRect, paintBorder);
    }
  }

  void _drawBird(Canvas canvas) {
    canvas.save();
    canvas.translate(GameEngine.birdX, gameEngine.birdY);
    canvas.rotate(gameEngine.birdRotation);

    // Bulbul Visuals (Pycnonotus jocosus)

    // Animation factor
    final double flap = sin(gameEngine.gameTime * 20); // -1 to 1

    // 1. Tail (Long, tapered, extending back)
    // Animate tail slightly
    canvas.save();
    canvas.rotate(flap * 0.05); // Slight tail wag
    final paintTail = Paint()..color = const Color(0xFF5D4037); // Dark Brown
    final tailPath = Path()
      ..moveTo(-15, 5)  // Start at back of body
      ..lineTo(-55, -5) // Tip of tail (upwards slightly)
      ..lineTo(-55, 15) // Width of tail tip
      ..lineTo(-15, 15) // Back to body
      ..close();
    canvas.drawPath(tailPath, paintTail);
    canvas.restore();

    // 3. Body (Brown Oval Main) - Draw body before wings
    final paintBody = Paint()..color = const Color(0xFF8D6E63); // Lighter Brown
    final bodyPath = Path()
      ..addOval(Rect.fromCenter(center: Offset.zero, width: 45, height: 32));
    canvas.drawPath(bodyPath, paintBody); // Draw body

    // 4. White Belly (Bottom clip)
    final paintBelly = Paint()..color = Colors.white;
    final bellyPath = Path()
      ..moveTo(-20, 5)
      ..quadraticBezierTo(0, 20, 25, 5)
      ..lineTo(25, 10)
      ..quadraticBezierTo(0, 28, -20, 10)
      ..close();
    canvas.drawPath(bellyPath, paintBelly);

    // 5. Head (Black)
    final paintHead = Paint()..color = Colors.black;
    canvas.drawCircle(const Offset(18, -10), 11, paintHead); 

    // 6. Crest (Sharp, pointing up/back)
    final crestPath = Path()
      ..moveTo(12, -18)
      ..lineTo(20, -35) // High sharp point
      ..lineTo(26, -15)
      ..close();
    canvas.drawPath(crestPath, paintHead);

    // 2. Wings (Darker brown teardrop on side) - ANIMATED
    canvas.save();
    canvas.translate(5, 0); // Pivot point for wing
    // Flap rotation: Map -1..1 to angle range
    // When rising (flap > 0), wing goes down? No, wing goes down to push up.
    // Let's just oscillate.
    canvas.rotate(flap * 0.5);
    final paintWing = Paint()..color = const Color(0xFF4E342E);
    final wingPath = Path()
      ..moveTo(-15, -5)
      ..quadraticBezierTo(15, 5, -10, 20) // Wing curve
      ..close();
    canvas.drawPath(wingPath, paintWing);
    canvas.restore();

    // 7. Red Vents/Whiskers
    final paintRed = Paint()..color = Colors.red;
    // Under tail coverts (Red patch under tail base)
    canvas.drawOval(Rect.fromCenter(center: const Offset(-20, 15), width: 10, height: 6), paintRed);
    // Cheek patch (Whisker)
    canvas.drawOval(Rect.fromCenter(center: const Offset(20, -8), width: 5, height: 5), paintRed);

    // 8. Beak
    final paintBeak = Paint()..color = Colors.black;
    final beakPath = Path()
      ..moveTo(28, -10)
      ..lineTo(38, -8)
      ..lineTo(28, -6)
      ..close();
    canvas.drawPath(beakPath, paintBeak);

    // 9. Eye
    final paintEye = Paint()..color = Colors.white;
    canvas.drawCircle(const Offset(22, -12), 2.5, paintEye);
    canvas.drawCircle(const Offset(22.5, -12.5), 1, Paint()..color = Colors.black); // Pupil

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
