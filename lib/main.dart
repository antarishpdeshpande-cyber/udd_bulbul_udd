import 'dart:async';
import 'package:flutter/material.dart';
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
        primarySwatch: Colors.orange,
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
  static const double gravity = 0.5;
  static const double jumpForce = -8.0;
  static const double birdSize = 40.0;
  static const double pillarWidth = 60.0;
  static const double pillarGap = 150.0;
  static const double pillarSpeed = 3.0;

  double birdY = 0;
  double birdVelocity = 0;
  double score = 0;
  int highScore = 0;
  bool isPlaying = false;
  bool isGameOver = false;

  List<Pillar> pillars = [];
  Timer? gameLoop;
  final String highScoreDocId = 'global_high_score';

  @override
  void initState() {
    super.initState();
    _loadHighScore();
  }

  Future<void> _loadHighScore() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('highscores')
          .doc(highScoreDocId)
          .get();
      if (doc.exists) {
        setState(() {
          highScore = (doc.data()?['score'] ?? 0) as int;
        });
      }
    } catch (e) {
      debugPrint('Error loading high score: $e');
    }
  }

  Future<void> _saveHighScore(int newScore) async {
    if (newScore > highScore) {
      setState(() {
        highScore = newScore;
      });
      try {
        await FirebaseFirestore.instance
            .collection('highscores')
            .doc(highScoreDocId)
            .set({'score': newScore});
      } catch (e) {
        debugPrint('Error saving high score: $e');
      }
    }
  }

  void startGame() {
    setState(() {
      birdY = 0;
      birdVelocity = 0;
      score = 0;
      isPlaying = true;
      isGameOver = false;
      pillars = [];
      _spawnPillar(initialOffset: 300); // offset first pillar
    });

    gameLoop?.cancel();
    gameLoop = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _updateGame();
    });
  }

  void _spawnPillar({double initialOffset = 0}) {
    // Random height between 20% and 60% of screen height
    final screenHeight = MediaQuery.of(context).size.height;
    final minHeight = screenHeight * 0.2;
    final maxHeight = screenHeight * 0.6;
    // Simple pseudo-random (using time)
    final height = minHeight +
        (DateTime.now().millisecondsSinceEpoch % 1000) /
            1000.0 *
            (maxHeight - minHeight);
            
    final startX = MediaQuery.of(context).size.width + initialOffset;

    pillars.add(Pillar(x: startX, height: height, passed: false));
  }

  void _updateGame() {
    if (!isPlaying) return;

    final screenHeight = MediaQuery.of(context).size.height;
    
    // Safety check just in case context is lost
    if (!mounted) return;

    setState(() {
      // Physics
      birdVelocity += gravity;
      birdY += birdVelocity;

      // Ground/Ceiling Collision
      if (birdY > screenHeight / 2 - birdSize / 2 || 
          birdY < -(screenHeight / 2 - birdSize / 2)) {
        gameOver();
      }

      // Pillar Logic
      for (int i = pillars.length - 1; i >= 0; i--) {
        pillars[i].x -= pillarSpeed;

        // Collision with pillars
        if (_checkCollision(pillars[i])) {
          gameOver();
        }

        // Score update
        if (!pillars[i].passed && pillars[i].x < (MediaQuery.of(context).size.width / 2) - birdSize) {
           score += 1;
           pillars[i].passed = true;
        }

        // Remove offscreen pillars
        if (pillars[i].x < -pillarWidth) {
          pillars.removeAt(i);
        }
      }

      // Spawn new pillars
      if (pillars.isNotEmpty) {
         if (pillars.last.x < MediaQuery.of(context).size.width - 250) { // spacing
           _spawnPillar();
         }
      } else {
         _spawnPillar(); // fallback if empty
      }
    });
  }

  bool _checkCollision(Pillar pillar) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Bird rect (centered)
    final birdLeft = (screenWidth / 2) - (birdSize / 2) + 5; // +5 padding
    final birdRight = (screenWidth / 2) + (birdSize / 2) - 5;
    final birdTop = (screenHeight / 2) + birdY + 5;
    final birdBottom = (screenHeight / 2) + birdY + birdSize - 5;

    // Pillar Rects
    // Top Pillar
    final topPillarBottom = pillar.height;
    // Bottom Pillar
    final bottomPillarTop = pillar.height + pillarGap;
    
    final pillarLeft = pillar.x;
    final pillarRight = pillar.x + pillarWidth;

    // Horizontal overlap
    if (birdRight > pillarLeft && birdLeft < pillarRight) {
      // Vertical overlap (Top Pillar OR Bottom Pillar)
      // Top pillar is from 0 to topPillarBottom.
      // But wait! our birdY is centered at 0. Let's align coordinate systems.
      // Screen coordinates approach:
      // birdTop is relative to top of screen (0). 
      // pillar.height is from top (0).
      
      // Top Pillar Collision
      if (birdTop < topPillarBottom) return true;
      
      // Bottom Pillar Collision
      if (birdBottom > bottomPillarTop) return true;
    }

    return false;
  }

  void gameOver() {
    gameLoop?.cancel();
    _saveHighScore(score.toInt());
    setState(() {
      isPlaying = false;
      isGameOver = true;
    });
  }

  void jump() {
    if (isGameOver) {
      startGame();
    } else if (!isPlaying) {
      startGame();
    } else {
      setState(() {
        birdVelocity = jumpForce;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: jump,
        child: Stack(
          children: [
            // Background (Indian Theme: Dawn Sky)
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFff9933), // Saffron (India Flag)
                    Colors.white,      // White
                    Color(0xFF138808), // Green (India Flag bottom hint)
                  ],
                  stops: [0.0, 0.5, 1.0], 
                ),
              ),
            ),
            
            // Silhouette (Taj Mahal / generic monuments)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: 0.3,
                child: Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/thumb/c/c8/Taj_Mahal_in_India_-_Kristian_Bertel.jpg/640px-Taj_Mahal_in_India_-_Kristian_Bertel.jpg', // Placeholder silhouette or image
                   height: 200,
                   fit: BoxFit.cover,
                   color: Colors.black, // Tint to make it a silhouette
                   colorBlendMode: BlendMode.srcATop,
                   errorBuilder: (c, o, s) => Container(height: 100, color: Colors.transparent),
                ),
              ),
            ),

            // Bird (Udd Bulbul!)
            if (isPlaying || !isPlaying) // always show centered
            Align(
              alignment: Alignment(0, birdY / (MediaQuery.of(context).size.height / 2)),
              child: Container(
                width: birdSize,
                height: birdSize,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.black26, blurRadius: 5, offset: Offset(2, 2))
                  ]
                ),
                child: const Center(child: Text('🦜', style: TextStyle(fontSize: 24))),
              ),
            ),

            // Pillars
            ...pillars.map((pillar) {
              return Stack(
                children: [
                  // Top Pillar
                  Positioned(
                    left: pillar.x,
                    top: 0,
                    width: pillarWidth,
                    height: pillar.height,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF5D4037), // Brown (Tree/Pillar)
                        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(10), bottomRight: Radius.circular(10)),
                        border: Border(bottom: BorderSide(color: Color(0xFFFFD700), width: 5)) // Gold trim
                      ),
                    ),
                  ),
                  // Bottom Pillar
                  Positioned(
                    left: pillar.x,
                    top: pillar.height + pillarGap,
                    width: pillarWidth,
                    bottom: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF5D4037),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10)),
                        border: Border(top: BorderSide(color: Color(0xFFFFD700), width: 5)) // Gold trim
                      ),
                    ),
                  ),
                ],
              );
            }).toList(),

            // UI Layer
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Score: ${score.toInt()}', 
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)
                        ),
                        Text(
                          'High Score: $highScore', 
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black54)
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Start / Game Over Screen
            if (!isPlaying && !isGameOver)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                       Text("Udd Bulbul Udd", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                       SizedBox(height: 10),
                       Text("Tap to Fly!", style: TextStyle(fontSize: 20)),
                    ],
                  ),
                ),
              ),

             if (isGameOver)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), borderRadius: BorderRadius.circular(15)),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       const Text("Game Over", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.red)),
                       Text("Score: ${score.toInt()}", style: const TextStyle(fontSize: 24)),
                       const SizedBox(height: 20),
                       ElevatedButton(
                         onPressed: startGame, 
                         style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)),
                         child: const Text("Play Again", style: TextStyle(fontSize: 20))
                       )
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

class Pillar {
  double x;
  double height;
  bool passed;

  Pillar({required this.x, required this.height, this.passed = false});
}
