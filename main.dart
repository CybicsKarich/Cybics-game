import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const CybicsApp());
}

class CybicsApp extends StatelessWidget {
  const CybicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cybics',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Segoe UI',
        brightness: Brightness.dark,
      ),
      home: const MainGameContainer(),
    );
  }
}

// --- КЛАССЫ ИГРОВЫХ ОБЪЕКТОВ ---
enum ObstacleType { spike, platform }

class Obstacle {
  final ObstacleType type;
  final double x;
  final double y;
  final double w;
  final double h;

  Obstacle({
    required this.type,
    required this.x,
    required this.y,
    this.w = 30.0,
    this.h = 30.0,
  });
}

class GameMedal {
  final int id;
  final double x;
  final double y;
  bool collected;

  GameMedal({required this.id, required this.x, required this.y, this.collected = false});
}

class Particle {
  double x;
  double y;
  double size;
  double opacity;

  Particle({required this.x, required this.y, required this.size, required this.opacity});
}

// --- ГЛАВНЫЙ ИНТЕРФЕЙС И СОСТОЯНИЯ ИГРЫ ---
class MainGameContainer extends StatefulWidget {
  const MainGameContainer({super.key});

  @override
  State<MainGameContainer> createState() => _MainGameContainerState();
}

class _MainGameContainerState extends State<MainGameContainer> with SingleTickerProviderStateMixin {
  // Навигация экранов: 
  // 0 - Меню, 1 - Выбор уровней, 2 - Настройки, 3 - Игра, 4 - Пауза, 5 - Рекорд, 6 - Победа
  int currentScreen = 0;
  bool isPaused = false;
  bool showPercentages = true;

  // Пасхалка бессмертия
  int titleClicks = 0;
  bool isGodMode = false;
  String mainTitleText = 'CYBICS';

  // Игровые параметры и рекорды
  int currentLevel = 1;
  String activeLevelName = 'START LEVEL';
  int currentProgress = 0;
  int currentRunAttempts = 1;

  int maxProgress = 0;
  int maxProgress2 = 0;
  int maxProgress3 = 0;

  int attempts1 = 0;
  int attempts2 = 0;
  int attempts3 = 0;

  List<bool> savedMedals1 = [false];
  List<bool> savedMedals2 = [false, false];
  List<bool> savedMedals3 = [false, false, false];

  // Движок звуков (Эмуляция музыкального секвенсора)
  double currentVolume = 0.5;
  double levelVolume = 0.5;
  bool inGameMode = false;
  Timer? synthTimer;
  int noteTick = 0;

  final List<double> menuNotes = [261.63, 329.63, 392.00, 523.25, 349.23, 440.00, 523.25, 587.33];
  final List<double> levelNotes1 = [130.81, 196.00, 164.81, 220.00, 130.81, 196.00, 293.66, 220.00];
  final List<double> levelNotes2 = [98.00, 98.00, 110.00, 87.31, 98.00, 146.83, 130.81, 73.42];
  final List<double> levelNotes3 = [110.00, 110.00, 110.00, 130.81, 98.00, 98.00, 87.31, 73.42];

  // Физический движок
  late AnimationController _gameLoopController;
  final double gameHeight = 600.0;
  final double floorY = 500.0;
  final double levelLength = 20000.0;

  double playerX = 100.0;
  double playerY = 460.0;
  double playerSize = 40.0;
  double velocityY = 0.0;
  double rotation = 0.0;
  bool isGrounded = true;
  bool isPressing = false;
  double cameraX = 0.0;

  List<Obstacle> obstacles = [];
  List<GameMedal> medals = [];
  List<int> collectedThisRun = [];
  List<Particle> trailParticles = [];

  @override
  void initState() {
    super.initState();
    _initAudio();
    
    // Цикл обновления кадров 60 FPS (Аналог requestAnimationFrame)
    _gameLoopController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))
      ..addListener(_updateGame);
  }

  @override
  void dispose() {
    synthTimer?.cancel();
    _gameLoopController.dispose();
    super.dispose();
  }

  // --- ЗВУКОВОЙ СЕКВЕНСОР ---
  void _initAudio() {
    synthTimer?.cancel();
    synthTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (isPaused && currentScreen == 4) return;
      noteTick++;
      
      if (inGameMode) {
        double currentNote = 0;
        String waveType = 'sawtooth';
        if (currentLevel == 1) {
          currentNote = levelNotes1[noteTick % levelNotes1.length];
        } else if (currentLevel == 2) {
          waveType = 'square';
          currentNote = levelNotes2[noteTick % levelNotes2.length];
        } else {
          currentNote = levelNotes3[noteTick % levelNotes3.length];
        }
        print('Синтезатор игры ($waveType): частота $currentNote Гц, громкость: $levelVolume');
      } else {
        if (currentScreen <= 2) {
          double currentNote = menuNotes[noteTick % menuNotes.length];
          print('Синтезатор меню (triangle): частота $currentNote Гц, громкость: $currentVolume');
        }
      }
    });
  }

  // --- ПАСХАЛКА: GOD MODE ---
  void _handleTitleClick() {
    if (isGodMode) return;
    setState(() {
      titleClicks++;
      if (titleClicks >= 10) {
        isGodMode = true;
        mainTitleText = 'GOD MODE';
        print('ПАСХАЛКА: Активировано бессмертие! Воспроизведение аккорда аккорда (523.25Гц, 659.25Гц, 783.99Гц)');
      }
    });
  }

  // --- ПРОЦЕДУРНЫЙ ГЕНЕРАТОР УРОВНЕЙ ПО СИДАМ ---
  double seededRandom(int seed) {
    double x = math.sin(seed.toDouble()) * 10000;
    return x - x.floorToDouble();
  }

  void generateFixedLevel() {
    obstacles.clear();
    medals.clear();
    collectedThisRun.clear();
    double nextX = 700.0;

    // Уровень 1
    if (currentLevel == 1) {
      int seed = 42;
      while (nextX < levelLength - 1000) {
        double r = seededRandom(seed++);
        if (r < 0.35) {
          obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX, y: floorY));
          nextX += 400 + seededRandom(seed++) * 200;
        } else if (r < 0.6) {
          obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX, y: floorY));
          obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 30, y: floorY));
          nextX += 500 + seededRandom(seed++) * 200;
        } else {
          double pWidth = 200 + (seededRandom(seed++) * 3).floor() * 60.0;
          double pHeight = 80.0;
          obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - pHeight, w: pWidth, h: pHeight));
          if (seededRandom(seed++) > 0.4) {
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + pWidth / 2 - 15, y: floorY - pHeight));
          }
          nextX += pWidth + 400 + seededRandom(seed++) * 200;
        }
      }
      medals.add(GameMedal(id: 0, x: levelLength * 0.52, y: floorY - 140));
    } 
    // Уровень 2
    else if (currentLevel == 2) {
      int seed = 999;
      while (nextX < levelLength - 1000) {
        double progressPct = (nextX / levelLength) * 100;
        bool isShipZone = progressPct >= 40 && progressPct <= 75;

        if (isShipZone) {
          double r = seededRandom(seed++);
          if (r < 0.5) {
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: 0, w: 60, h: 180));
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 180, w: 60, h: 180));
          } else {
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 100, w: 80, h: 100));
          }
          nextX += 600 + seededRandom(seed++) * 200;
        } else {
          double r = seededRandom(seed++);
          if (r < 0.4) {
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 60, w: 160, h: 60));
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX + 220, y: floorY - 120, w: 160, h: 120));
            nextX += 600;
          } else if (r < 0.7) {
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 70, w: 300, h: 70));
            nextX += 650;
          } else {
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX, y: floorY));
            nextX += 450;
          }
        }
      }
      medals.add(GameMedal(id: 0, x: levelLength * 0.22, y: floorY - 150));
      medals.add(GameMedal(id: 1, x: levelLength * 0.435, y: floorY - 30));
    } 
    // Уровень 3
    else {
      int seed = 888;
      bool spawnedTrap = false;
      bool spawnedShipTrap = false;
      bool spawnedSecretChain = false;

      while (nextX < levelLength - 1000) {
        double progressPct = (nextX / levelLength) * 100;
        bool isShipZone = progressPct >= 40 && progressPct <= 75;

        if (isShipZone) {
          if (!spawnedShipTrap && progressPct > 52) {
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: 0, w: 280, h: 40));
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: 190, w: 280, h: 40));
            medals.add(GameMedal(id: 1, x: nextX + 140, y: 115));

            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 10, y: 230));
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 90, y: 230));
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 170, y: 230));
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 250, y: 230));

            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 100, w: 280, h: 100));
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 40, y: floorY - 100));
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 120, y: floorY - 100));
            obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 200, y: floorY - 100));

            nextX += 600;
            spawnedShipTrap = true;
          } else {
            double r = seededRandom(seed++);
            if (r < 0.4) {
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX - 80, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: 240, w: 60, h: 120));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX - 15, y: 300));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 15, y: 240));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 40, y: 300));
              nextX += 450;
            } else if (r < 0.7) {
              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: 0, w: 200, h: 140));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 20, y: 170));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 90, y: 170));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 160, y: 170));

              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 80, w: 200, h: 80));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 10, y: floorY - 80));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 80, y: floorY - 80));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 150, y: floorY - 80));
              nextX += 500;
            } else {
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 30, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 60, y: floorY));
              nextX += 400;
            }
          }
        } else {
          if (!spawnedSecretChain && progressPct >= 77.5) {
            obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 70, w: 200, h: 70));
            double p1X = nextX + 240;
            double p1Y = floorY - 140;
            obstacles.add(Obstacle(type: ObstacleType.platform, x: p1X, y: p1Y, w: 80, h: 25));

            double p2X = p1X + 160;
            double p2Y = floorY - 210;
            obstacles.add(Obstacle(type: ObstacleType.platform, x: p2X, y: p2Y, w: 80, h: 25));
            medals.add(GameMedal(id: 2, x: p2X + 40, y: p2Y - 25));

            nextX = p2X + 250;
            spawnedSecretChain = true;
          } 
          else if (!spawnedTrap && progressPct > 6 && progressPct < 15) {
            double currentY = floorY;
            for (int i = 0; i < 5; i++) {
              currentY -= 50;
              double gapShift = (i >= 2) ? 40.0 : 0.0;
              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX + (i * 180) + gapShift, y: currentY, w: 120, h: 50));
            }
            double platform6X = nextX + (5 * 180) + 40;
            obstacles.add(Obstacle(type: ObstacleType.platform, x: platform6X, y: currentY - 50, w: 120, h: 50));
            obstacles.add(Obstacle(type: ObstacleType.spike, x: platform6X + 90, y: currentY - 50));
            medals.add(GameMedal(id: 0, x: nextX + (2 * 180) - 10, y: floorY - 30));

            nextX += (6 * 180) + 40 + 350;
            spawnedTrap = true;
          } else {
            double r = seededRandom(seed++);
            if (r < 0.25) {
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 30, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 60, y: floorY));
              nextX += 500;
            } else if (r < 0.50) {
              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX, y: floorY - 40, w: 100, h: 40));
              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX + 180, y: floorY - 100, w: 120, h: 100));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 260, y: floorY - 100));
              nextX += 550;
            } else if (r < 0.75) {
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX + 40, y: floorY - 60, w: 200, h: 60));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 280, y: floorY));
              nextX += 520;
            } else {
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.spike, x: nextX + 30, y: floorY));
              obstacles.add(Obstacle(type: ObstacleType.platform, x: nextX + 180, y: floorY - 80, w: 80, h: 80));
              nextX += 480;
            }
          }
        }
      }
    }
  }

  // --- ФИЗИЧЕСКИЙ ДВИЖОК ОБНОВЛЕНИЯ КООРДИНАТ ---
  void _updateGame() {
    if (isPaused) return;

    setState(() {
      playerX += 7.5;
      cameraX = playerX - 200.0;

      double progressPct = (playerX / levelLength) * 100;
      bool playerIsShip = ((currentLevel == 2 || currentLevel == 3) && progressPct >= 40 && progressPct <= 75);

      // Добавление следа (Неонового шлейфа)
      trailParticles.add(Particle(x: playerX + playerSize / 2, y: playerY + playerSize / 2, size: 0, opacity: 1.0));
      if (trailParticles.length > 15) trailParticles.removeAt(0);

      // Управление физикой высоты
      if (playerIsShip) {
        if (isPressing) velocityY -= 0.9; else velocityY += 0.7;
        velocityY = velocityY.clamp(-8.0, 8.0);
        playerY += velocityY;
        isGrounded = false;
        if (playerY <= 100) { playerY = 100; velocityY = 0; }
        rotation = velocityY * 0.04;
      } else {
        velocityY += 1.5; // Гравитация
        playerY += velocityY;
        isGrounded = false;
      }

      if (playerY >= floorY - playerSize) {
        playerY = floorY - playerSize;
        velocityY = 0;
        isGrounded = true;
      }

      currentProgress = math.min(100, progressPct.floor());

      // Проверка монеток (Радиус сбора)
      for (var m in medals) {
        if (!m.collected) {
          double distX = ((playerX + playerSize / 2) - m.x).abs();
          double distY = ((playerY + playerSize / 2) - m.y).abs();
          if (distX < 35 && distY < 35) {
            m.collected = true;
            if (!collectedThisRun.contains(m.id)) collectedThisRun.add(m.id);
          }
        }
      }

      // Столкновения с препятствиями
      for (var obs in obstacles) {
        if (obs.type == ObstacleType.spike) {
          if (playerX + playerSize > obs.x + 8 && playerX < obs.x + 22 &&
              ((obs.y == floorY && playerY + playerSize > obs.y - 30 && playerY < obs.y) || 
               (obs.y != floorY && playerY < obs.y && playerY + playerSize > obs.y - 30))) {
            if (!isGodMode) { _gameOver(); return; }
          }
        } else if (obs.type == ObstacleType.platform) {
          if (playerX + playerSize > obs.x + 4 && playerX < obs.x + obs.w - 4 &&
              playerY + playerSize >= obs.y && playerY + playerSize <= obs.y + 20 && velocityY >= 0) {
            playerY = obs.y - playerSize;
            velocityY = 0;
            isGrounded = true;
          } 
          else if (playerX + playerSize > obs.x && playerX < obs.x + obs.w &&
                   playerY + playerSize > obs.y + 15 && playerY < obs.y + obs.h) {
            if (!isGodMode) { _gameOver(); return; }
          }
        }
      }

      // Прыжок кубика
      if (!playerIsShip && isPressing && isGrounded) {
        velocityY = -20.0;
        isGrounded = false;
      }

      if (!playerIsShip) {
        if (!isGrounded) rotation += 0.08;
        else rotation = (rotation / (math.pi / 2)).round() * (math.pi / 2);
      }

      // Проверка финиша
      if (playerX >= levelLength) {
        _gameLoopController.stop();
        _triggerVictory();
      }
    });
  }

  void _gameOver() {
    _gameLoopController.stop();
    print('ЗВУК СМЕРТИ: частота 180Гц -> 30Гц');
    bool isNewRecord = false;

    if (currentLevel == 1 && currentProgress > maxProgress && currentProgress < 100) { maxProgress = currentProgress; isNewRecord = true; }
    if (currentLevel == 2 && currentProgress > maxProgress2 && currentProgress < 100) { maxProgress2 = currentProgress; isNewRecord = true; }
    if (currentLevel == 3 && currentProgress > maxProgress3 && currentProgress < 100) { maxProgress3 = currentProgress; isNewRecord = true; }

    void registerNewAttempt() {
      setState(() {
        currentRunAttempts++;
        if (currentLevel == 1 && maxProgress < 100) attempts1++;
        if (currentLevel == 2 && maxProgress2 < 100) attempts2++;
        if (currentLevel == 3 && maxProgress3 < 100) attempts3++;
      });
    }

    if (isNewRecord) {
      setState(() => currentScreen = 5); // Экран нового рекорда
      Timer(const Duration(milliseconds: 1200), () {
        registerNewAttempt();
        _restartLevel();
      });
    } else {
      registerNewAttempt();
      _restartLevel();
    }
  }

  void _triggerVictory() {
    setState(() {
      if (currentLevel == 1) { maxProgress = 100; collectedThisRun.forEach((id) => savedMedals1[id] = true); }
      if (currentLevel == 2) { maxProgress2 = 100; collectedThisRun.forEach((id) => savedMedals2[id] = true); }
      if (currentLevel == 3) { maxProgress3 = 100; collectedThisRun.forEach((id) => savedMedals3[id] = true); }
      inGameMode = false;
      currentScreen = 6; // Экран победы
    });
  }

  void _restartLevel() {
    setState(() {
      playerX = 100.0;
      playerY = floorY - playerSize;
      velocityY = 0.0;
      cameraX = 0.0;
      currentProgress = 0;
      rotation = 0.0;
      isGrounded = true;
      trailParticles.clear();
      collectedThisRun.clear();
      currentScreen = 3;
      generateFixedLevel();
      _gameLoopController.repeat();
    });
  }

  void _launchGameplay(int levelIndex, String name) {
    setState(() {
      currentLevel = levelIndex;
      activeLevelName = name;
      inGameMode = true;
      isPaused = false;
      currentRunAttempts = 1;
      currentScreen = 3;

      if (currentLevel == 1 && maxProgress < 100) attempts1++;
      if (currentLevel == 2 && maxProgress2 < 100) attempts2++;
      if (currentLevel == 3 && maxProgress3 < 100) attempts3++;

      generateFixedLevel();
      _gameLoopController.repeat();
    });
  }

  // --- СБОРКА ТЕМПЛЕЙТОВ ЭКРАНОВ И ИНТЕРФЕЙСА ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF1A1A2E), Color(0xFF16213E)])),
        child: Center(
          child: Container(
            width: (currentScreen >= 3) ? double.infinity : 800,
            height: (currentScreen >= 3) ? double.infinity : 500,
            decoration: (currentScreen >= 3) ? null : BoxDecoration(
              color: const Color(0xFF0F172A),
              border: Border.all(color: const Color(0xFF3B82F6), width: 4),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                _buildMainScreenContent(),
                if (isPaused && currentScreen == 4) _buildPauseOverlay(),
                if (currentScreen == 5) _buildNewRecordOverlay(),
                if (currentScreen == 6) _buildVictoryOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainScreenContent() {
    switch (currentScreen) {
      case 0: return _buildMainMenu();
      case 1: return _buildLevelsMenu();
      case 2: return _buildSettingsMenu();
      case 3: return _buildGameplayScreen();
      default: return _buildMainMenu();
    }
  }

  Widget _buildMainMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: _handleTitleClick,
            child: Text(
              mainTitleText,
              style: TextStyle(
                fontSize: 64, fontWeight: FontWeight.black,
                color: isGodMode ? const Color(0xFFE11D48) : const Color(0xFF00F2FE),
                shadows: [Shadow(color: isGodMode ? const Color(0xFFF43F5E) : const Color(0xFF00F2FE).withOpacity(0.6), blurRadius: 20)],
              ),
            ),
          ),
          const SizedBox(height: 50),
          _buildButton('Играть', () => setState(() => currentScreen = 1)),
          _buildButton('Настройки', () => setState(() => currentScreen = 2), isSecondary: true),
        ],
      ),
    );
  }

  Widget _buildLevelsMenu() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Text('Выбор уровня', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const Spacer(),
          Wrap(
            spacing: 15, runSpacing: 15, alignment: WrapAlignment.center,
            children: [
              _buildLevelCard('START LEVEL', attempts1, maxProgress, const Color(0xFF475569), savedMedals1, () => _launchGameplay(1, 'START LEVEL')),
              _buildLevelCard('NOT BAD', attempts2, maxProgress2, const Color(0xFFA855F7), savedMedals2, () => _launchGameplay(2, 'NOT BAD'), titleColor: const Color(0xFFC084FC)),
                        _buildLevelCard('TRY AND CRY', attempts3, maxProgress3, const Color(0xFFEF4444), savedMedals3, () => _launchGameplay(3, 'TRY AND CRY'), titleColor: const Color(0xFFF87171)),
            ],
          ),
          const Spacer(),
          _buildButton('Назад', () => setState(() => currentScreen = 0), isSecondary: true, minWidth: 200),
        ],
      ),
    );
  }

  // ======= НАСТРОЙКИ =======
  Widget _buildSettingsMenu() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Настройки', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 40),
          const Text('Громкость музыки', style: TextStyle(fontSize: 18, color: Color(0xFF94A3B8))),
          SizedBox(
            width: 300,
            child: Slider(
              value: currentVolume * 100, min: 0, max: 100,
              activeColor: const Color(0xFF00F2FE),
              onChanged: (val) => setState(() => currentVolume = val / 100),
            ),
          ),
          Text('${(currentVolume * 100).toInt()}%'),
          const SizedBox(height: 30),
          _buildButton('Назад', () => setState(() => currentScreen = 0), isSecondary: true, minWidth: 200),
        ],
      ),
    );
  }

  // ======= ЭКРАН ГЕЙМПЛЕЯ =======
  Widget _buildGameplayScreen() {
    double progressPct = (playerX / levelLength) * 100;
    bool playerIsShip = ((currentLevel == 2 || currentLevel == 3) && progressPct >= 40 && progressPct <= 75);

    return Container(
      color: const Color(0xFF0F172A),
      child: Stack(
        children: [
          // Рендеринг игрового мира (Canvas)
          Positioned.fill(
            child: GestureDetector(
              onTapDown: (_) => isPressing = true,
              onTapUp: (_) => isPressing = false,
              onTapCancel: () => isPressing = false,
              child: CustomPaint(
                painter: GamePainter(
                  cameraX: cameraX,
                  playerX: playerX,
                  playerY: playerY,
                  playerSize: playerSize,
                  rotation: rotation,
                  floorY: floorY,
                  obstacles: obstacles,
                  medals: medals,
                  particles: trailParticles,
                  currentLevel: currentLevel,
                  currentProgress: currentProgress,
                  isShip: playerIsShip,
                  showPercentages: showPercentages,
                  levelLength: levelLength,
                ),
              ),
            ),
          ),
          // Счетчик попыток в левом верхнем углу
          Positioned(
            top: 20, left: 20,
            child: Text(
              isGodMode ? 'БЕССМЕРТИЕ' : 'Попытка $currentRunAttempts',
              style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.black,
                color: isGodMode ? const Color(0xFFE11D48) : Colors.white,
                shadows: [
                  Shadow(
                    color: isGodMode ? const Color(0xFFF43F5E) : Colors.black.withOpacity(0.8),
                    blurRadius: 10, offset: const Offset(0, 2),
                  )
                ],
              ),
            ),
          ),
          // Кнопка Паузы в правом верхнем углу
          Positioned(
            top: 20, right: 20,
            child: GestureDetector(
              onTap: () => setState(() {
                isPaused = true;
                currentScreen = 4; // Открыть паузу
              }),
              child: Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(child: Text('⏸', style: TextStyle(fontSize: 24, color: Colors.white))),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ======= ОВЕРЛЕЙ ПАУЗЫ =======
  Widget _buildPauseOverlay() {
    int currentRecord = currentLevel == 1 ? maxProgress : (currentLevel == 2 ? maxProgress2 : maxProgress3);
    return Container(
      color: Colors.black.withOpacity(0.9),
      width: double.infinity, height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Пауза', style: TextStyle(fontSize: 44, color: Color(0xFF00F2FE), fontWeight: FontWeight.bold)),
          Text('Рекорд: $currentRecord%', style: const TextStyle(fontSize: 18, color: Color(0xFF94A3B8))),
          const SizedBox(height: 20),
          const Text('Громкость в уровне'),
          SizedBox(
            width: 300,
            child: Slider(
              value: levelVolume * 100, min: 0, max: 100,
              activeColor: const Color(0xFF00F2FE),
              onChanged: (val) => setState(() => levelVolume = val / 100),
            ),
          ),
          SizedBox(
            width: 350,
            child: CheckboxListTile(
              title: const Text('Показывать проценты (%) во время игры', style: TextStyle(fontSize: 14)),
              value: showPercentages,
              activeColor: const Color(0xFF00F2FE),
              onChanged: (val) => setState(() => showPercentages = val ?? true),
            ),
          ),
          const SizedBox(height: 20),
          _buildButton('Продолжить', () => setState(() {
            isPaused = false;
            currentScreen = 3;
          })),
          _buildButton('В меню', () => setState(() {
            currentScreen = 0;
            inGameMode = false;
            isPaused = false;
            _gameLoopController.stop();
          }), isSecondary: true),
        ],
      ),
    );
  }

  // ======= ОВЕРЛЕЙ НОВОГО РЕКОРДА =======
  Widget _buildNewRecordOverlay() {
    return Container(
      color: const Color(0xFF0F172A).withOpacity(0.7),
      width: double.infinity, height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Новый рекорд!',
            style: TextStyle(
              fontSize: 54, fontWeight: FontWeight.black, color: const Color(0xFFE11D48),
              letterSpacing: 4,
              shadows: [Shadow(color: const Color(0xFFE11D48).withOpacity(0.6), blurRadius: 20)],
            ),
          ),
          const SizedBox(height: 20),
          Text('$currentProgress%', style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  // ======= ОВЕРЛЕЙ ПОБЕДЫ =======
  Widget _buildVictoryOverlay() {
    return Container(
      color: const Color(0xFF0F172A).withOpacity(0.9),
      width: double.infinity, height: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Уровень пройден!',
            style: TextStyle(
              fontSize: 54, fontWeight: FontWeight.black, color: const Color(0xFF22C55E),
              letterSpacing: 4,
              shadows: [Shadow(color: const Color(0xFF22C55E).withOpacity(0.8), blurRadius: 30)],
            ),
          ),
          const SizedBox(height: 15),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Новый рекорд: ', style: TextStyle(fontSize: 32, color: Color(0xFFF1F5F9))),
              Text('100%', style: TextStyle(fontSize: 32, color: Color(0xFF4ADE80), fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 40),
          _buildButton('ОК', () => setState(() {
            currentScreen = 1; // Возврат к выбору уровней
          })),
        ],
      ),
    );
  }

  // Шаблон кнопок (.btn и .btn-secondary)
  Widget _buildButton(String text, VoidCallback onPressed, {bool isSecondary = false, double minWidth = 250}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      width: minWidth, height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        gradient: isSecondary ? null : const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF06B6D4)]),
        color: isSecondary ? const Color(0xFF334155) : null,
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
        onPressed: onPressed,
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  // Шаблон карточки уровня (.level-card)
  Widget _buildLevelCard(String title, int attempts, int progress, Color borderColor, List<bool> medals, VoidCallback onTap, {Color titleColor = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF1E293B), border: Border.all(color: borderColor, width: 2), borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Попыток: $attempts', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: titleColor)),
            const SizedBox(height: 8),
            Row(children: medals.map((hasMedal) => Opacity(opacity: hasMedal ? 1.0 : 0.2, child: const Text('🥇', style: TextStyle(fontSize: 18)))).toList()),
            const SizedBox(height: 10),
            Container(
              width: double.infinity, height: 20,
              decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text('$progress%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
            )
          ],
        ),
      ),
    );
  }
}

// =======ОТРИСОВЩИК ГРАФИКИ (Аналог drawGame) =======
class GamePainter extends CustomPainter {
  final double cameraX;
  final double playerX;
  final double playerY;
  final double playerSize;
  final double rotation;
  final double floorY;
  final List<Obstacle> obstacles;
  final List<GameMedal> medals;
  final List<Particle> particles;
  final int currentLevel;
  final int currentProgress;
  final bool isShip;
  final bool showPercentages;
  final double levelLength;

  GamePainter({
    required this.cameraX,
    required this.playerX,
    required this.playerY,
    required this.playerSize,
    required this.rotation,
    required this.floorY,
    required this.obstacles,
    required this.medals,
    required this.particles,
    required this.currentLevel,
    required this.currentProgress,
    required this.isShip,
    required this.showPercentages,
    required this.levelLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    double scale = size.height / 600.0;
    canvas.scale(scale, scale);
    double viewWidth = size.width / scale;

    // Фон
    paint.shader = const LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
    ).createShader(Rect.fromLTWH(0, 0, viewWidth, 600));
    canvas.drawRect(Rect.fromLTWH(0, 0, viewWidth, 600), paint);
    paint.shader = null;

    // Пол
    double maxFloorW = (levelLength - cameraX).clamp(0.0, viewWidth);
    if (maxFloorW > 0) {
      paint.color = const Color(0xFF1E293B);
      canvas.drawRect(Rect.fromLTWH(0, floorY, maxFloorW, 600 - floorY), paint);
      paint.color = const Color(0xFF3B82F6);
      paint.strokeWidth = 4;
      canvas.drawLine(Offset(0, floorY), Offset(maxFloorW, floorY), paint);
    }

    canvas.save();
    canvas.translate(-cameraX, 0);

    // Шлейф
    if (particles.length > 1) {
      paint.style = PaintingStyle.stroke;
      paint.strokeCap = StrokeCap.round;
      paint.strokeJoin = StrokeJoin.round;
      paint.strokeWidth = isShip ? 4 : 6;
      for (int i = 1; i < particles.length; i++) {
        double alpha = (i / particles.length) * 0.6;
        paint.color = isShip ? const Color(0xFFC084FC).withOpacity(alpha) : const Color(0xFF00F2FE).withOpacity(alpha);
        canvas.drawLine(Offset(particles[i - 1].x, particles[i - 1].y), Offset(particles[i].x, particles[i].y), paint);
      }
      paint.style = PaintingStyle.fill;
    }

    // Порталы смены режима (40% и 75%)
    if (currentLevel == 2 || currentLevel == 3) {
      for (double pX in [levelLength * 0.4, levelLength * 0.75]) {
        if (pX - cameraX > -100 && pX - cameraX < viewWidth + 100) {
          paint.shader = LinearGradient(
            colors: [const Color(0xFFA855F7).withOpacity(0), const Color(0xFFA855F7).withOpacity(0.4), const Color(0xFFA855F7).withOpacity(0)],
          ).createShader(Rect.fromLTWH(pX - 20, 100, 40, floorY - 100));
          canvas.drawRect(Rect.fromLTWH(pX - 20, 100, 40, floorY - 100), paint);
          paint.shader = null;
          paint.color = const Color(0xFFC084FC);
          paint.strokeWidth = 6;
          canvas.drawLine(Offset(pX, 100), Offset(pX, floorY), paint);
        }
      }
    }

    // Препятствия
    for (var obs in obstacles) {
      if (obs.x - cameraX > -200 && obs.x - cameraX < viewWidth + 200) {
        if (obs.type == ObstacleType.spike) {
          paint.color = const Color(0xFFEF4444);
          var path = Path()..moveTo(obs.x, obs.y)..lineTo(obs.x + 30, obs.y)..lineTo(obs.x + 15, obs.y - 30)..close();
          canvas.drawPath(path, paint);
        } else {
          paint.color = const Color(0xFF334155);
          canvas.drawRect(Rect.fromLTWH(obs.x, obs.y, obs.w, obs.h), paint);
        }
      }
    }

    // Медали
    for (var m in medals) {
      if (!m.collected && m.x - cameraX > -50 && m.x - cameraX < viewWidth + 50) {
        paint.color = const Color(0xFFF59E0B);
        canvas.drawCircle(Offset(m.x, m.y), 18, paint);
        final tp = TextPainter(text: const TextSpan(text: 'C', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
        tp.paint(canvas, Offset(m.x - tp.width / 2, m.y - tp.height / 2));
      }
    }

    // Финишный портал
    double portalX = levelLength;
    if (portalX - cameraX > -200 && portalX - cameraX < viewWidth + 200) {
      paint.shader = RadialGradient(colors: [Colors.white.withOpacity(0.9), const Color(0xFF4ADE80).withOpacity(0.8), const Color(0xFF22C55E).withOpacity(0)]).createShader(Rect.fromCircle(center: Offset(portalX, floorY - 150), radius: 150));
      canvas.drawOval(Rect.fromCenter(center: Offset(portalX, floorY - 150), width: 180, height: 300), paint);
      paint.shader = null;
    }

    canvas.restore();

    // Кубик / Самолётик
    canvas.save();
    canvas.translate(playerX - cameraX + playerSize / 2, playerY + playerSize / 2);
    canvas.rotate(rotation);
    if (isShip) {
      paint.color = const Color(0xFFC084FC);
      var path = Path()..moveTo(-playerSize / 2, 0)..lineTo(playerSize / 2, -playerSize / 4)..lineTo(playerSize / 4, playerSize / 2)..close();
      canvas.drawPath(path, paint);
    } else {
      paint.color = const Color(0xFF00F2FE);
      canvas.drawRect(Rect.fromLTWH(-playerSize / 2, -playerSize / 2, playerSize, playerSize), paint);
    }
    canvas.restore();

    // Индикатор прогресса
    if (showPercentages) {
      double barW = 250, barH = 22, barX = viewWidth / 2 - barW / 2, barY = 25;
      paint.color = const Color(0xFF0F172A).withOpacity(0.6);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW, barH), paint);
      paint.color = const Color(0xFF00F2FE);
      canvas.drawRect(Rect.fromLTWH(barX, barY, barW * (currentProgress / 100), barH), paint);
      final tp = TextPainter(text: TextSpan(text: '$currentProgress%', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(barX + barW / 2 - tp.width / 2, barY + 11 - tp.height / 2));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

