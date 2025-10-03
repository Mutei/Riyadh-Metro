import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ShimmerBoxes {
  static Widget rounded({
    double width = double.infinity,
    double height = 16,
    BorderRadiusGeometry radius = const BorderRadius.all(Radius.circular(12)),
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
      ),
    );
  }
}

/// Full‑screen map shimmer to use while location/map is “warming up”.
class MapLoadingShimmer extends StatelessWidget {
  const MapLoadingShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFEAEAEA),
      highlightColor: const Color(0xFFF6F6F6),
      child: Stack(
        children: [
          // big background
          Positioned.fill(
            child: Container(color: Colors.white),
          ),

          // mimic some “map tiles” texture with large rectangles
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                  18,
                  (_) => ShimmerBoxes.rounded(
                    height: 80,
                    radius: const BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),
            ),
          ),

          // top pills (profile/bell) placeholders
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShimmerBoxes.rounded(
                      width: 44, height: 44, radius: BorderRadius.circular(22)),
                  ShimmerBoxes.rounded(
                      width: 44, height: 44, radius: BorderRadius.circular(22)),
                ],
              ),
            ),
          ),

          // center banner placeholder (metro/car banner)
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ShimmerBoxes.rounded(width: 280, height: 64),
              ),
            ),
          ),

          // bottom right FABs
          Positioned(
            right: 12,
            bottom: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ShimmerBoxes.rounded(
                    width: 155, height: 44, radius: BorderRadius.circular(22)),
                const SizedBox(height: 10),
                ShimmerBoxes.rounded(
                    width: 170, height: 44, radius: BorderRadius.circular(22)),
              ],
            ),
          ),

          // bottom draggable sheet handle + two fields placeholders
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF6F9F3),
                borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShimmerBoxes.rounded(
                      width: 40, height: 4, radius: BorderRadius.circular(100)),
                  const SizedBox(height: 14),
                  ShimmerBoxes.rounded(width: 180, height: 26),
                  const SizedBox(height: 12),
                  ShimmerBoxes.rounded(
                      height: 44, radius: BorderRadius.circular(12)),
                  const SizedBox(height: 10),
                  ShimmerBoxes.rounded(
                      height: 44, radius: BorderRadius.circular(12)),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Use in places where you were showing a "center spinner in a dialog"
class BusyShimmerDialog extends StatelessWidget {
  final String? title;
  final String? subtitle;
  const BusyShimmerDialog({super.key, this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 6,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Shimmer.fromColors(
              baseColor: const Color(0xFFE0E0E0),
              highlightColor: const Color(0xFFF2F2F2),
              child: ShimmerBoxes.rounded(
                  width: 28, height: 28, radius: BorderRadius.circular(14)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null && title!.isNotEmpty)
                    Text(title!,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(subtitle!,
                        style: const TextStyle(color: Colors.black54)),
                  ],
                  const SizedBox(height: 10),
                  Shimmer.fromColors(
                    baseColor: const Color(0xFFE0E0E0),
                    highlightColor: const Color(0xFFF4F4F4),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      color: Colors.white,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
