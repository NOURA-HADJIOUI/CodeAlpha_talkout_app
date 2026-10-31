import 'package:flutter/material.dart';
import '../theme/colors.dart';

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  final bool online;
  final String? imageUrl;
  const Avatar(this.name, {super.key, this.size = 48, this.online = false, this.imageUrl});
  static const _colors = [
    Color(0xFFF59E0B), Color(0xFF3B82F6), Color(0xFFEC4899),
    Color(0xFF10B981), Color(0xFF8B5CF6), Color(0xFFEF4444),
  ];
  @override
  Widget build(BuildContext context) {
    final c = _colors[(name.isEmpty ? 0 : name.codeUnitAt(0)) % _colors.length];
    return Stack(children: [
      CircleAvatar(
        radius: size / 2,
        backgroundColor: c,
        child: imageUrl == null
            ? _initial(name, size)
            : ClipOval(
                child: Image.network(
                  imageUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _initial(name, size),
                ),
              ),
      ),
      if (online)
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * .26,
            height: size * .26,
            decoration: BoxDecoration(
              color: kGreen,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
    ]);
  }

  Widget _initial(String value, double diameter) => Text(
        value.isEmpty ? '?' : value[0].toUpperCase(),
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: diameter * .4),
      );
}

class Logo extends StatelessWidget {
  final double size;
  const Logo({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(size * .3)),
        child: Icon(Icons.chat_bubble_rounded, color: Colors.white, size: size * .55),
      );
}

class Brand extends StatelessWidget {
  final double size;
  const Brand({super.key, this.size = 24});
  @override
  Widget build(BuildContext context) => Text.rich(
        const TextSpan(children: [
          TextSpan(text: 'Talk', style: TextStyle(color: kText)),
          TextSpan(text: 'Out', style: TextStyle(color: kPrimary)),
        ]),
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w800),
      );
}
