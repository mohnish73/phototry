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

  late Animation<double> _fade;
  late Animation<double> _xScale;
  late Animation<double> _oScale;
  late Animation<double> _loadBar;
  late Animation<double> _glow;

  String _loadText = 'LOADING BOARD...';

  static const _bg     = Color(0xFF07071A);
  static const _card   = Color(0xFF0F0F2A);
  static const _purple = Color(0xFF7B2FBE);
  static const _glowC  = Color(0xFFAA55FF);
  static const _xColor = Color(0xFFFF4C6E);
  static const _oColor = Color(0xFF00D4FF);

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400));
    _loadCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200));
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: const Interval(0.0, 0.25)));
    _xScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.1, 0.55, curve: Curves.elasticOut)));
    _oScale = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
            parent: _logoCtrl,
            curve: const Interval(0.45, 0.9, curve: Curves.elasticOut)));
    _loadBar = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _loadCtrl, curve: Curves.easeInOut));
    _glow = Tween<double>(begin: 8.0, end: 28.0)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));

    _loadCtrl.addListener(() {
      final v = _loadCtrl.value;
      if (v < 0.35 && _loadText != 'LOADING BOARD...') {
        setState(() => _loadText = 'LOADING BOARD...');
      } else if (v >= 0.35 && v < 0.7 && _loadText != 'SETTING UP AI...') {
        setState(() => _loadText = 'SETTING UP AI...');
      } else if (v >= 0.7 && v < 1.0 && _loadText != 'ALMOST READY...') {
        setState(() => _loadText = 'ALMOST READY...');
      } else if (v >= 1.0 && _loadText != 'GAME READY!') {
        setState(() => _loadText = 'GAME READY!');
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
      backgroundColor: _bg,
      body: Stack(
        children: [
          CustomPaint(
            painter: _GridBgPainter(),
            size: MediaQuery.of(context).size,
          ),
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_logoCtrl, _glowCtrl]),
              builder: (_, __) => Opacity(
                opacity: _fade.value,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // X  VS  O
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _symbolCard(_xScale, _xColor, isX: true),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          child: Text(
                            'VS',
                            style: TextStyle(
                              color: _glowC,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 3,
                              shadows: [
                                Shadow(
                                    color: _purple.withOpacity(0.9),
                                    blurRadius: 12),
                              ],
                            ),
                          ),
                        ),
                        _symbolCard(_oScale, _oColor, isX: false),
                      ],
                    ),
                    const SizedBox(height: 36),

                    // Title
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [_glowC, Colors.white, _glowC],
                      ).createShader(bounds),
                      child: const Text(
                        'TIC  TAC  TOE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'THINK  •  PLAY  •  WIN',
                      style: TextStyle(
                        color: _glowC,
                        fontSize: 11,
                        letterSpacing: 3,
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
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A3E),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: _loadBar.value,
                                  child: Container(
                                    height: 8,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      gradient: const LinearGradient(
                                        colors: [_xColor, _purple, _oColor],
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
                              color: _glowC,
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
            ),
          ),
        ],
      ),
    );
  }

  Widget _symbolCard(Animation<double> scaleAnim, Color color,
      {required bool isX}) {
    return ScaleTransition(
      scale: scaleAnim,
      child: AnimatedBuilder(
        animation: _glowCtrl,
        builder: (_, __) => Container(
          width: 86,
          height: 86,
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.55), width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.45),
                blurRadius: _glow.value,
                spreadRadius: 1,
              ),
            ],
          ),
          child: CustomPaint(
            painter:
                isX ? _XPainter(color: color) : _OPainter(color: color),
          ),
        ),
      ),
    );
  }
}

class _GridBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7B2FBE).withOpacity(0.07)
      ..strokeWidth = 1;

    const cell = 72.0;
    const pad = cell / 3;

    for (double gx = 0; gx < size.width + cell * 2; gx += cell * 3.8) {
      for (double gy = 20; gy < size.height + cell * 2; gy += cell * 3.8) {
        canvas.drawLine(Offset(gx + pad, gy), Offset(gx + pad, gy + cell), paint);
        canvas.drawLine(
            Offset(gx + pad * 2, gy), Offset(gx + pad * 2, gy + cell), paint);
        canvas.drawLine(Offset(gx, gy + pad), Offset(gx + cell, gy + pad), paint);
        canvas.drawLine(
            Offset(gx, gy + pad * 2), Offset(gx + cell, gy + pad * 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _XPainter extends CustomPainter {
  final Color color;
  const _XPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final glow = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final p = size.width * 0.22;
    canvas.drawLine(Offset(p, p), Offset(size.width - p, size.height - p), glow);
    canvas.drawLine(Offset(size.width - p, p), Offset(p, size.height - p), glow);
    canvas.drawLine(Offset(p, p), Offset(size.width - p, size.height - p), paint);
    canvas.drawLine(Offset(size.width - p, p), Offset(p, size.height - p), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _OPainter extends CustomPainter {
  final Color color;
  const _OPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.32;

    final glow = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke;

    canvas.drawCircle(center, radius, glow);
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}