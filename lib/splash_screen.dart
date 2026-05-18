import 'package:flutter/material.dart';
import 'game_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoCtrl;
  late AnimationController _loadCtrl;
  late AnimationController _glowCtrl;

  late Animation<double> _scale;
  late Animation<double> _fade;
  late Animation<double> _loadBar;
  late Animation<double> _glow;

  String _loadText = 'INITIALIZING...';

  static const _bgDark = Color(0xFF07071A);
  static const _purple = Color(0xFF7B2FBE);
  static const _purpleGlow = Color(0xFFAA55FF);

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000));
    _loadCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.4)));
    _loadBar = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _loadCtrl, curve: Curves.easeInOut));
    _glow = Tween<double>(begin: 10.0, end: 35.0)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _loadCtrl.addListener(() {
      final v = _loadCtrl.value;
      if (v < 0.3 && _loadText != 'INITIALIZING...') {
        setState(() => _loadText = 'INITIALIZING...');
      } else if (v >= 0.3 && v < 0.7 && _loadText != 'LOADING ASSETS...') {
        setState(() => _loadText = 'LOADING ASSETS...');
      } else if (v >= 0.7 && v < 1.0 && _loadText != 'ALMOST READY...') {
        setState(() => _loadText = 'ALMOST READY...');
      } else if (v >= 1.0 && _loadText != 'READY!') {
        setState(() => _loadText = 'READY!');
      }
    });

    _logoCtrl.forward().then((_) {
      _loadCtrl.forward().then((_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const GameHomeScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 700),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _loadCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Stack(
        children: [
          // Background grid dots
          CustomPaint(
            painter: _GridPainter(),
            size: MediaQuery.of(context).size,
          ),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo with glow
                AnimatedBuilder(
                  animation: Listenable.merge([_logoCtrl, _glowCtrl]),
                  builder: (_, __) => Opacity(
                    opacity: _fade.value,
                    child: Transform.scale(
                      scale: _scale.value,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [_purpleGlow, _purple, Color(0xFF3A0066)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _purple.withOpacity(0.7),
                              blurRadius: _glow.value,
                              spreadRadius: _glow.value * 0.3,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.auto_awesome,
                            size: 64, color: Colors.white),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                AnimatedBuilder(
                  animation: _logoCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _fade.value,
                    child: Column(
                      children: [
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_purpleGlow, Colors.white, _purpleGlow],
                          ).createShader(bounds),
                          child: const Text(
                            'GALLERY QUEST',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'BACKUP  •  PROTECT  •  COLLECT',
                          style: TextStyle(
                            color: _purpleGlow,
                            fontSize: 11,
                            letterSpacing: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 70),

                // Loading bar
                AnimatedBuilder(
                  animation: _loadCtrl,
                  builder: (_, __) => Column(
                    children: [
                      SizedBox(
                        width: 240,
                        child: Stack(
                          children: [
                            Container(
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A3E),
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: _loadBar.value,
                              child: Container(
                                height: 10,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  gradient: const LinearGradient(
                                    colors: [_purple, _purpleGlow],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _purple.withOpacity(0.6),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _loadText,
                        style: const TextStyle(
                          color: _purpleGlow,
                          fontSize: 11,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7B2FBE).withOpacity(0.08)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
