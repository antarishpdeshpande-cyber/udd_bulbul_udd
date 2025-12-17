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
    timeSinceSpawn = 0;
    _spawnPillar(initialOffset: 400);
  }

  void jump() {
    birdVelocity = jumpForce;
  }

  void update(double dt) {
    if (gameState != GameState.playing) return;
    if (dt > 0.1) dt = 0.1; // Cap dt to prevent huge jumps

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
    // Sky Gradient (Light Blue -> Lighter Blue)
    final Rect rect = Offset.zero & size;
    final Paint skyPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF87CEEB), Color(0xFFE0F7FA)],
      ).createShader(rect);
    canvas.drawRect(rect, skyPaint);

    // Sun
    final paintSun = Paint()..color = Colors.yellow;
    canvas.drawCircle(Offset(size.width * 0.8, 80), 30, paintSun);

    // Clouds (Simple white circles)
    final paintCloud = Paint()..color = Colors.white.withOpacity(0.8);
    canvas.drawCircle(Offset(size.width * 0.2, 100), 20, paintCloud);
    canvas.drawCircle(Offset(size.width * 0.23, 90), 25, paintCloud);
    canvas.drawCircle(Offset(size.width * 0.26, 100), 20, paintCloud);

    // Taj Mahal Implementation
    // Drawn centered at bottom
    final paintTaj = Paint()..color = Colors.white;
    final paintTajShadow = Paint()..color = Colors.grey[300]!;
    
    final centerX = size.width / 2;
    final bottomY = size.height - 50; // Ground line
    
    // Main Platform
    canvas.drawRect(Rect.fromCenter(center: Offset(centerX, bottomY - 10), width: 300, height: 20), paintTaj);
    
    // Central Structure (Box)
    canvas.drawRect(Rect.fromCenter(center: Offset(centerX, bottomY - 70), width: 140, height: 100), paintTaj);
    
    // Central Arch (Iwan)
    final archPath = Path()
      ..moveTo(centerX - 20, bottomY - 20)
      ..lineTo(centerX - 20, bottomY - 80)
      ..arcToPoint(Offset(centerX + 20, bottomY - 80), radius: const Radius.circular(20))
      ..lineTo(centerX + 20, bottomY - 20)
      ..close();
    canvas.drawPath(archPath, paintTajShadow);

    // Central Dome (Bulbous)
    final domePath = Path()
      ..moveTo(centerX - 40, bottomY - 120)
      ..quadraticBezierTo(centerX - 50, bottomY - 150, centerX, bottomY - 180) // Left curve
      ..quadraticBezierTo(centerX + 50, bottomY - 150, centerX + 40, bottomY - 120) // Right curve
      ..close();
    canvas.drawPath(domePath, paintTaj);
    
    // Finial (Spire on dome)
    canvas.drawRect(Rect.fromCenter(center: Offset(centerX, bottomY - 180), width: 4, height: 20), Paint()..color = Colors.gold);

    // Side Domes (Smaller)
    void drawSideDome(double dx) {
      canvas.drawRect(Rect.fromCenter(center: Offset(dx, bottomY - 120), width: 30, height: 30), paintTaj);
       final smallDome = Path()
        ..moveTo(dx - 15, bottomY - 135)
        ..quadraticBezierTo(dx, bottomY - 155, dx + 15, bottomY - 135)
        ..close();
      canvas.drawPath(smallDome, paintTaj);
    }
    drawSideDome(centerX - 50);
    drawSideDome(centerX + 50);

    // Minarets
    void drawMinaret(double dx) {
       final minaretPath = Path()
        ..moveTo(dx - 5, bottomY)
        ..lineTo(dx - 3, bottomY - 150)
        ..lineTo(dx + 3, bottomY - 150)
        ..lineTo(dx + 5, bottomY)
        ..close();
       canvas.drawPath(minaretPath, paintTaj);
       // Minaret dome
       canvas.drawOval(Rect.fromCenter(center: Offset(dx, bottomY - 150), width: 10, height: 10), paintTaj);
    }
    drawMinaret(centerX - 120);
    drawMinaret(centerX + 120);
    drawMinaret(centerX - 80); // Inner minarets (perspective)
    drawMinaret(centerX + 80);

    // Ground
    final paintGround = Paint()..color = const Color(0xFFDEB887); // Sand color
    canvas.drawRect(Rect.fromLTWH(0, bottomY, size.width, 50), paintGround);
  }

  void _drawPillars(Canvas canvas) {
    final paintPillar = Paint()..color = const Color(0xFF2E7D32); // Green marble/plants
    final paintBorder = Paint()
      ..color = const Color(0xFF1B5E20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    for (var p in gameEngine.pillars) {
      final w = GameEngine.pillarWidth;
      final gapHalf = GameEngine.pillarGap / 2;
      
      // Top Pillar
      final topRect = Rect.fromLTRB(p.x, -1000, p.x + w, p.gapCenter - gapHalf);
      canvas.drawRect(topRect, paintPillar);
      canvas.drawRect(topRect, paintBorder);
      
      // Bottom Pillar
      final bottomRect = Rect.fromLTRB(p.x, p.gapCenter + gapHalf, p.x + w, 1000);
      canvas.drawRect(bottomRect, paintPillar);
      canvas.drawRect(bottomRect, paintBorder);
    }
  }

  void _drawBird(Canvas canvas) {
    canvas.save();
    canvas.translate(GameEngine.birdX, gameEngine.birdY);
    canvas.rotate(gameEngine.birdRotation);

    // Bulbul Visuals (Pycnonotus jocosus)
    // Detailed drawing based on reference: Long tail, brown back, white belly, black crest, red whiskers.

    // 1. Tail (Long, tapered, extending back)
    final paintTail = Paint()..color = const Color(0xFF5D4037); // Dark Brown
    final tailPath = Path()
      ..moveTo(-15, 5)  // Start at back of body
      ..lineTo(-55, -5) // Tip of tail (upwards slightly)
      ..lineTo(-55, 15) // Width of tail tip
      ..lineTo(-15, 15) // Back to body
      ..close();
    canvas.drawPath(tailPath, paintTail);

    // 2. Wings (Darker brown teardrop on side)
    final paintWing = Paint()..color = const Color(0xFF4E342E);
    final wingPath = Path()
      ..moveTo(-10, -5)
      ..quadraticBezierTo(20, 5, -5, 20) // Wing curve
      ..close();
    
    // 3. Body (Brown Oval Main)
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

    canvas.drawPath(wingPath, paintWing); // Draw wing over body

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
