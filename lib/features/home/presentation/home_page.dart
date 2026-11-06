import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';

import '../../../app/routes/app_routes.dart';
import '../../../app/theme/app_colors.dart';
import '../../../core/database/memory_dao.dart';
import '../../../core/models/memory.dart';
import '../../../core/widgets/pocket_widgets.dart';
import '../controller/home_controller.dart';
import 'widgets/memory_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final HomeController controller = Get.find<HomeController>();
  final ScrollController _scroll = ScrollController();
  late final Worker _scrollWorker;

  @override
  void initState() {
    super.initState();
    _scrollWorker = ever<int>(controller.scrollToTopTick, (int _) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollWorker.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool wide = constraints.maxWidth >= 840;
            return RefreshIndicator(
              color: AppColors.accentText(brightness),
              onRefresh: () => controller.reload(),
              child: CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: <Widget>[
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      wide ? 32.w : 20.w,
                      18.h,
                      wide ? 32.w : 20.w,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: wide ? 980 : double.infinity,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _Header(controller: controller),
                              SizedBox(height: 18.h),
                              _SearchEntry(),
                              SizedBox(height: 16.h),
                              _Banner(controller: controller),
                              _FilterBar(controller: controller),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  _Timeline(controller: controller, wide: wide),
                  // Clears the capture FAB so the last card stays fully legible.
                  SliverToBoxAdapter(child: SizedBox(height: 96.h)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'MINDPOCKET',
                style: text.labelSmall?.copyWith(
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                  color: AppColors.accentText(brightness),
                ),
              ),
              SizedBox(height: 6.h),
              Obx(
                () => Text(
                  controller.totalCount.value == 0
                      ? 'Your pocket is ready'
                      : 'Your pocket',
                  style: text.displaySmall,
                ),
              ),
              SizedBox(height: 6.h),
              Obx(() {
                final int pending = controller.pendingJobs.value;
                return Text(
                  pending == 0
                      ? 'Screenshots, voice notes, and thoughts in one searchable place.'
                      : '$pending item${pending == 1 ? '' : 's'} being processed on this device.',
                  style: text.bodySmall,
                );
              }),
            ],
          ),
        ),
        SizedBox(width: 12.w),
        Obx(
          () => IconButton.filledTonal(
            onPressed: () =>
                controller.setSort(oldest: !controller.oldestFirst.value),
            tooltip: controller.oldestFirst.value
                ? 'Sorted oldest first. Switch to newest first'
                : 'Sorted newest first. Switch to oldest first',
            icon: Icon(
              controller.oldestFirst.value
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchEntry extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Semantics(
      button: true,
      label: 'Search your memories',
      child: Material(
        color: AppColors.surface(brightness),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
          side: BorderSide(color: AppColors.border(brightness)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Get.toNamed(AppRoutes.search),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: AppColors.textSecondary(brightness),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    'Search notes, screenshots, and transcripts',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: AppColors.textSecondary(brightness)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    return Obx(() {
      final String message = controller.banner.value;
      if (message.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: PocketCard(
          padding: EdgeInsets.fromLTRB(16.w, 10.h, 6.w, 10.h),
          color: AppColors.highlight(brightness).withValues(alpha: 0.18),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: AppColors.textPrimary(brightness),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: AppColors.textPrimary(brightness)),
                ),
              ),
              IconButton(
                onPressed: controller.dismissBanner,
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Dismiss',
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final MemoryFilter current = controller.filter.value;
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.only(right: 12.w),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            for (final MemoryFilter filter in MemoryFilter.values)
              Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: PocketChip(
                  label: filter.label,
                  selected: current == filter,
                  onTap: () => controller.setFilter(filter),
                ),
              ),
          ],
        ),
      );
    });
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.controller, required this.wide});

  final HomeController controller;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.loading.value && controller.memories.isEmpty) {
        return SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 32.w : 20.w,
            vertical: 12.h,
          ),
          sliver: SliverList.builder(
            itemCount: 4,
            itemBuilder: (BuildContext context, int index) => Padding(
              padding: EdgeInsets.only(bottom: 12.h),
              child: const _CardSkeleton(),
            ),
          ),
        );
      }

      if (controller.error.value.isNotEmpty && controller.memories.isEmpty) {
        return SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 32.w : 20.w,
            vertical: 16.h,
          ),
          sliver: SliverToBoxAdapter(
            child: ErrorBlock(
              message: controller.error.value,
              onRetry: () => controller.reload(),
            ),
          ),
        );
      }

      if (controller.memories.isEmpty) {
        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 32.w : 20.w),
          sliver: SliverToBoxAdapter(
            child: _EmptyTimeline(filter: controller.filter.value),
          ),
        );
      }

      Widget buildRow(BuildContext context, int index) {
        final Memory memory = controller.memories[index];
        if (index >= controller.memories.length - 4) {
          controller.loadMore();
        }
        return MemoryCard(
          key: ValueKey<String>(memory.id),
          memory: memory,
          onTap: () => Get.toNamed(AppRoutes.memory(memory.id)),
          onFavorite: () => controller.toggleFavorite(memory),
          onRetry: () => controller.retryJobs(memory),
          onDelete: () => _confirmDelete(context, memory),
        );
      }

      // Cards must grow with enlarged text, so phones use a list with natural
      // heights; only the two-column tablet layout fixes a cell height.
      if (!wide) {
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 0),
          sliver: SliverList.separated(
            itemCount: controller.memories.length,
            itemBuilder: buildRow,
            separatorBuilder: (BuildContext context, int index) =>
                SizedBox(height: 12.h),
          ),
        );
      }

      // Same 980px column as the header, so the grid lines up with it instead of
      // drifting to the screen edges.
      return SliverPadding(
        padding: EdgeInsets.fromLTRB(32.w, 4.h, 32.w, 0),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 164,
                ),
                itemCount: controller.memories.length,
                itemBuilder: buildRow,
              ),
            ),
          ),
        ),
      );
    });
  }

  Future<void> _confirmDelete(BuildContext context, Memory memory) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Delete this memory?'),
        content: const Text(
          'The images, recordings, extracted text, and its place in search are removed. '
          'Downloaded speech models are kept.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteMemory(memory);
  }
}

class _EmptyTimeline extends StatelessWidget {
  const _EmptyTimeline({required this.filter});

  final MemoryFilter filter;

  @override
  Widget build(BuildContext context) {
    final String title = switch (filter) {
      MemoryFilter.all => 'Nothing in your pocket yet',
      MemoryFilter.images => 'No screenshots yet',
      MemoryFilter.voice => 'No voice notes yet',
      MemoryFilter.notes => 'No written notes yet',
      MemoryFilter.favorites => 'Nothing starred yet',
    };
    final String message = switch (filter) {
      MemoryFilter.all => 'Capture a screenshot, record a thought, or type a note. Everything is stored on this device.',
      MemoryFilter.images => 'Import a screenshot to extract its text locally.',
      MemoryFilter.voice => 'Record a thought. Audio stays playable even before a speech model is installed.',
      MemoryFilter.notes => 'Write a note. Typed notes are fully searchable.',
      MemoryFilter.favorites => 'Tap the star on any memory to keep it close.',
    };
    return EmptyState(
      title: title,
      message: message,
      actionLabel: 'Open capture',
      onAction: () => Get.toNamed(AppRoutes.capture),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color base = AppColors.raised(brightness);
    return PocketCard(
      padding: EdgeInsets.all(14.r),
      child: Row(
        children: <Widget>[
          Container(
            width: 82.r,
            height: 82.r,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(18.r),
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Bar(width: 160.w, height: 14),
                SizedBox(height: 10.h),
                _Bar(width: double.infinity, height: 10),
                SizedBox(height: 8.h),
                _Bar(width: 120.w, height: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.raised(Theme.of(context).brightness),
      borderRadius: BorderRadius.circular(999),
    ),
  );
}
