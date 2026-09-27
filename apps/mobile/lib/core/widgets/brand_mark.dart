import 'package:dg_chat/app/localization/localization.dart';
import 'package:dg_chat/app/theme/app_theme.dart';
import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: context.l10n.appName,
      child: SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.gold,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.chat_bubble_rounded,
                color: AppColors.deepTeal,
                size: size * 0.48,
              ),
              Positioned(
                right: size * 0.12,
                top: size * 0.12,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox.square(dimension: size * 0.18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
