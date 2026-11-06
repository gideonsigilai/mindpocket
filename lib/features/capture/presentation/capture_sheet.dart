import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/widgets/collage_art.dart';
import '../../../core/widgets/pocket_widgets.dart';

/// Bottom sheet offering the three real capture paths. Every option performs a
/// real action; nothing here is decorative.
class CaptureSheet extends StatelessWidget {
  const CaptureSheet({super.key});

  static Future<void> show(BuildContext context) async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => const CaptureSheet(),
    );
    if (choice == null) return;
    switch (choice) {
      case 'image':
        Get.toNamed(
          AppRoutes.capture,
          arguments: <String, Object?>{'mode': 'image'},
        );
      case 'voice':
        Get.toNamed(
          AppRoutes.capture,
          arguments: <String, Object?>{'mode': 'voice'},
        );
      case 'note':
        Get.toNamed(
          AppRoutes.capture,
          arguments: <String, Object?>{'mode': 'note'},
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 20.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Capture something',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 4.h),
            Text(
              'It stays on this device. Processing happens after the file is safely saved.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            SizedBox(height: 18.h),
            _Option(
              icon: Icons.image_outlined,
              title: 'Screenshot or image',
              subtitle: 'Import from the gallery. Text is extracted locally.',
              variant: CollageVariant.capture,
              onTap: () => Navigator.of(context).pop('image'),
            ),
            SizedBox(height: 12.h),
            _Option(
              icon: Icons.mic_none_rounded,
              title: 'Voice note',
              subtitle: 'Record with pause and resume. Transcribe offline when a model is installed.',
              variant: CollageVariant.voice,
              onTap: () => Navigator.of(context).pop('voice'),
            ),
            SizedBox(height: 12.h),
            _Option(
              icon: Icons.edit_note_rounded,
              title: 'Written note',
              subtitle: 'Type a thought, add tags, and search it instantly.',
              variant: CollageVariant.search,
              onTap: () => Navigator.of(context).pop('note'),
            ),
            SizedBox(height: 16.h),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Not now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.variant,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final CollageVariant variant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return PocketCard(
      onTap: onTap,
      padding: EdgeInsets.all(14.r),
      semanticLabel: '$title. $subtitle',
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(16.r),
            child: Container(
              color: AppColors.raised(brightness),
              width: 74.r,
              height: 74.r,
              child: CollageArt(
                variant: variant,
                height: 74.r,
                showGrain: false,
              ),
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      icon,
                      size: 16,
                      color: AppColors.accentText(brightness),
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary(brightness),
          ),
        ],
      ),
    );
  }
}
