import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/layout/app_breakpoints.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/day_entry.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/services/app_theme_service.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/screens/camera/camera_screen.dart';
import 'package:photo_per_day/services/gallery_photo_service.dart';
import 'package:photo_per_day/widgets/photo_source_sheet.dart';

/// Dedicated Photo Detail Screen for viewing, editing, and managing photo memories.
///
/// Features:
/// - Prominent hero photo view
/// - Intra-day photo browsing for multi-photo days
/// - Add, delete, and reorder controls for photos in this date
/// - Shared daily note presentation and editing
/// - Local photo title and location metadata editing
/// - Destructive delete confirmation with note-preservation logic
class PhotoDetailScreen extends StatefulWidget {
  const PhotoDetailScreen({
    super.key,
    required this.photoEntry,
    this.onDeleteConfirmed,
  });

  final PhotoEntry photoEntry;
  final VoidCallback? onDeleteConfirmed;

  @override
  State<PhotoDetailScreen> createState() => _PhotoDetailScreenState();
}

class _PhotoDetailScreenState extends State<PhotoDetailScreen> {
  final GalleryPhotoService _galleryPhotoService = GalleryPhotoService();

  late PhotoEntry _currentEntry;
  DayEntry? _dayEntry;
  bool _isEditing = false;
  late PageController _heroPageController;

  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    final store = PersistentDailyPhotoStore.instance;
    _dayEntry = store.getDay(widget.photoEntry.dateKey);

    final matchingPhoto =
        _dayEntry?.getPhotoById(widget.photoEntry.effectiveId) ??
        _dayEntry?.getPhotoById(widget.photoEntry.id) ??
        _dayEntry?.primaryPhoto ??
        widget.photoEntry;

    _currentEntry = matchingPhoto;

    final initialIdx = _dayEntry != null && _dayEntry!.photos.isNotEmpty
        ? _dayEntry!.photos.indexWhere(
            (p) =>
                p.effectiveId == _currentEntry.effectiveId ||
                p.id == _currentEntry.id,
          )
        : 0;
    _heroPageController = PageController(
      initialPage: initialIdx >= 0 ? initialIdx : 0,
    );

    _titleController = TextEditingController(text: _currentEntry.title);
    _locationController = TextEditingController(
      text: _currentEntry.location ?? '',
    );
    _noteController = TextEditingController(text: _dayEntry?.note ?? '');

    store.addListener(_onPhotoStoreUpdated);
    AppThemeService.instance.addListener(_onPhotoStoreUpdated);
  }

  void _onPhotoStoreUpdated() {
    if (!mounted) return;
    final store = PersistentDailyPhotoStore.instance;
    final updatedDay = store.getDay(_currentEntry.dateKey);

    setState(() {
      _dayEntry = updatedDay;
      if (updatedDay != null && updatedDay.hasPhotos) {
        final updatedPhoto =
            updatedDay.getPhotoById(_currentEntry.effectiveId) ??
            updatedDay.getPhotoById(_currentEntry.id) ??
            updatedDay.primaryPhoto;

        if (updatedPhoto != null) {
          _currentEntry = updatedPhoto;
          if (!_isEditing) {
            _titleController.text = updatedPhoto.title;
            _locationController.text = updatedPhoto.location ?? '';
            _noteController.text = updatedDay.note;
          }
          final newIdx = updatedDay.photos.indexWhere(
            (p) =>
                p.effectiveId == updatedPhoto.effectiveId ||
                p.id == updatedPhoto.id,
          );
          if (newIdx >= 0 &&
              _heroPageController.hasClients &&
              _heroPageController.page?.round() != newIdx) {
            _heroPageController.jumpToPage(newIdx);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    PersistentDailyPhotoStore.instance.removeListener(_onPhotoStoreUpdated);
    AppThemeService.instance.removeListener(_onPhotoStoreUpdated);
    _heroPageController.dispose();
    _titleController.dispose();
    _locationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _openSwipeDays() {
    Navigator.of(
      context,
    ).pushNamed(AppConstants.swipeDaysRoute, arguments: _currentEntry);
  }

  void _enterEditMode() {
    setState(() {
      _titleController.text = _currentEntry.title;
      _locationController.text = _currentEntry.location ?? '';
      _noteController.text = _dayEntry?.note ?? '';
      _isEditing = true;
    });
  }

  /// Whether the user has modified any diary field since entering edit mode.
  bool get _hasUnsavedChanges {
    final currentTitle = _titleController.text.trim();
    final currentLocation = _locationController.text.trim();
    final currentNote = _noteController.text.trim();

    final originalTitle = _currentEntry.title.trim();
    final originalLocation = (_currentEntry.location ?? '').trim();
    final originalNote = (_dayEntry?.note ?? '').trim();

    return currentTitle != originalTitle ||
        currentLocation != originalLocation ||
        currentNote != originalNote;
  }

  /// Prompts the user before discarding unsaved edits.
  Future<bool> _onWillPop() async {
    if (!_isEditing || !_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: Text(
          'Discard changes?',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'You have unsaved changes to this diary entry. Are you sure you want to discard them?',
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Keep Editing',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Discard',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _cancelEditMode() async {
    if (_hasUnsavedChanges) {
      final shouldDiscard = await _onWillPop();
      if (!shouldDiscard) return;
    }
    setState(() {
      _titleController.text = _currentEntry.title;
      _locationController.text = _currentEntry.location ?? '';
      _noteController.text = _dayEntry?.note ?? '';
      _isEditing = false;
    });
  }

  Future<void> _saveChanges() async {
    final updatedTitle = _titleController.text.trim();
    if (updatedTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title cannot be empty.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final rawLocation = _locationController.text.trim();
    final updatedLocation = rawLocation.isEmpty ? null : rawLocation;
    final updatedNote = _noteController.text.trim();

    try {
      // 1. Update Photo Metadata (title, location)
      final updatedPhoto = _currentEntry.copyWith(
        title: updatedTitle,
        location: updatedLocation,
        lastModifiedAt: DateTime.now().toUtc(),
      );
      await PersistentDailyPhotoStore.instance.savePhoto(entry: updatedPhoto);

      // 2. Update Day Note
      final updatedDay = await PersistentDailyPhotoStore.instance.updateDayNote(
        dateKey: _currentEntry.dateKey,
        note: updatedNote,
      );

      if (mounted) {
        setState(() {
          _dayEntry = updatedDay;
          _currentEntry = updatedPhoto;
          _isEditing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Diary entry saved.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to save photo metadata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save changes. Please try again.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _triggerMockShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sharing "${_currentEntry.title}"...'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Adds a photo to this specific calendar day
  Future<void> _addPhotoToDay() async {
    final source = await PhotoSourceSheet.show(context);
    if (source == null || !mounted) return;

    String? capturedPath;
    if (source == PhotoSource.camera) {
      capturedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );
    } else if (source == PhotoSource.gallery) {
      capturedPath = await _galleryPhotoService.pickPhoto();
    }

    if (capturedPath != null && capturedPath.isNotEmpty && mounted) {
      final now = DateTime.now();
      final period = now.hour >= 12 ? 'PM' : 'AM';
      final hour12 = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final minuteFormatted = now.minute.toString().padLeft(2, '0');
      final formattedTime = '$hour12:$minuteFormatted $period';

      final newPhoto = PhotoEntry(
        date: _currentEntry.dateKey.toDateTime(
          hour: now.hour,
          minute: now.minute,
        ),
        title: 'New Memory',
        location: source == PhotoSource.camera
            ? 'Camera Capture'
            : 'Photo Library',
        timeFormatted: formattedTime,
        imagePath: capturedPath,
        gradientColors: [AppColors.accent, AppColors.surfaceDark],
      );

      try {
        final saved = await PersistentDailyPhotoStore.instance.addPhotoToDay(
          dateKey: _currentEntry.dateKey,
          photo: newPhoto,
          sourceTempPath: capturedPath,
        );

        if (mounted) {
          final updatedDay = PersistentDailyPhotoStore.instance.getDay(
            _currentEntry.dateKey,
          );
          setState(() {
            _dayEntry = updatedDay;
            _currentEntry = saved;
            _titleController.text = saved.title;
            _locationController.text = saved.location ?? '';
          });

          if (updatedDay != null) {
            final newIdx = updatedDay.photos.indexWhere(
              (p) => p.effectiveId == saved.effectiveId || p.id == saved.id,
            );
            if (newIdx >= 0 && _heroPageController.hasClients) {
              _heroPageController.jumpToPage(newIdx);
            }
          }

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo added to this day.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to add photo: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  /// Replaces the currently displayed photo with a new capture/selection
  Future<void> _replaceCurrentPhoto() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: Text(
          'Replace Photo',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to replace this photo with a new capture? Other photos on this date will remain unchanged.',
          style: TextStyle(
            fontSize: 14.0,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryButtonBackground,
              foregroundColor: AppColors.primaryButtonForeground,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
            child: const Text('Replace'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final source = await PhotoSourceSheet.show(context);
    if (source == null || !mounted) return;

    String? capturedPath;
    if (source == PhotoSource.camera) {
      capturedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const CameraScreen()),
      );
    } else if (source == PhotoSource.gallery) {
      capturedPath = await _galleryPhotoService.pickPhoto();
    }

    if (capturedPath != null && capturedPath.isNotEmpty && mounted) {
      try {
        final updatedPhoto = _currentEntry.copyWith(
          imagePath: capturedPath,
          lastModifiedAt: DateTime.now().toUtc(),
        );

        final saved = await PersistentDailyPhotoStore.instance.savePhoto(
          entry: updatedPhoto,
          sourceTempPath: capturedPath,
        );

        if (mounted) {
          final updatedDay = PersistentDailyPhotoStore.instance.getDay(
            _currentEntry.dateKey,
          );
          setState(() {
            _dayEntry = updatedDay;
            _currentEntry = saved;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo replaced successfully.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to replace photo: $e'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  /// Opens dialog to reorder photos for this day
  Future<void> _showReorderDialog() async {
    final day = _dayEntry;
    if (day == null || day.photos.length <= 1) return;

    final reorderedList = List<PhotoEntry>.from(day.photos);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Reorder Photos',
                          style: AppTypography.sectionTitle.copyWith(
                            fontSize: 18.0,
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4.0),
                    Text(
                      'Drag to change display order for this date. First photo is primary.',
                      style: AppTypography.caption,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 300.0,
                      child: ReorderableListView.builder(
                        itemCount: reorderedList.length,
                        onReorderItem: (oldIndex, newIndex) {
                          setModalState(() {
                            final item = reorderedList.removeAt(oldIndex);
                            reorderedList.insert(newIndex, item);
                          });
                          final ids = reorderedList
                              .map((p) => p.effectiveId)
                              .toList();
                          PersistentDailyPhotoStore.instance.reorderPhotos(
                            dateKey: day.dateKey,
                            orderedPhotoIds: ids,
                          );
                        },
                        itemBuilder: (context, index) {
                          final photo = reorderedList[index];
                          final isPrimary = index == 0;
                          return ListTile(
                            key: ValueKey('reorder_${photo.effectiveId}'),
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6.0),
                              child: SizedBox(
                                width: 44.0,
                                height: 44.0,
                                child:
                                    (photo.hasRealImage &&
                                        photo.isImageFileAvailable)
                                    ? Image.file(
                                        File(photo.imagePath!),
                                        fit: BoxFit.cover,
                                      )
                                    : _buildFallbackThumbnail(photo),
                              ),
                            ),
                            title: Text(
                              photo.title.isNotEmpty
                                  ? photo.title
                                  : 'Photo ${index + 1}',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isPrimary
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              isPrimary
                                  ? 'Primary cover photo'
                                  : photo.timeFormatted,
                              style: TextStyle(
                                fontSize: 11.0,
                                color: isPrimary
                                    ? AppColors.accent
                                    : AppColors.textMuted,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.drag_handle_rounded,
                              size: 20.0,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Deletes the selected photo. If it's the last photo, retains note or prompts safely.
  Future<void> _showDeleteConfirmationDialog() async {
    final day = _dayEntry;
    final totalPhotosInDay = day?.photoCount ?? 1;
    final hasDailyNote = day?.hasNote ?? false;
    final isLastPhoto = totalPhotosInDay <= 1;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: Text(
          isLastPhoto ? 'Delete Memory?' : 'Delete This Photo?',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          isLastPhoto
              ? (hasDailyNote
                    ? 'This is the last photo for this date. The photo will be permanently deleted, but your daily note will be preserved.'
                    : 'This action is irreversible. The photo and entry for this day will be permanently deleted from your local diary.')
              : 'Remove this photo from this day’s collection? Other photos on this date will be kept intact.',
          style: AppTypography.body.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final store = PersistentDailyPhotoStore.instance;
        final updatedDay = await store.removePhotoById(
          dateKey: _currentEntry.dateKey,
          photoId: _currentEntry.effectiveId,
          preserveNoteOnlyDay: true,
        );

        widget.onDeleteConfirmed?.call();

        if (mounted) {
          if (updatedDay != null && updatedDay.hasPhotos) {
            // Day still has other photos; switch to the primary photo
            setState(() {
              _dayEntry = updatedDay;
              _currentEntry = updatedDay.primaryPhoto!;
              _titleController.text = _currentEntry.title;
              _locationController.text = _currentEntry.location ?? '';
            });

            if (_heroPageController.hasClients) {
              _heroPageController.jumpToPage(0);
            }

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Photo deleted.'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // No photos remain; pop back to calendar/diary
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  hasDailyNote
                      ? 'Photo deleted. Daily note preserved.'
                      : 'Memory deleted.',
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Failed to delete photo from detail screen: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Unable to delete memory. Please try again.'),
              duration: Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isEditing || !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop(result);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: AppColors.current.isDark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: AppColors.current.isDark
              ? Brightness.dark
              : Brightness.light,
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () async {
              final shouldPop = await _onWillPop();
              if (shouldPop && context.mounted) {
                Navigator.of(context).maybePop();
              }
            },
          },
          child: Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppBreakpoints.maxContentWidth,
                  ),
                  child: Column(
                    children: [
                      // Minimal Detail Header
                      _buildHeader(),

                      // Scrollable Detail Content
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.pageHorizontal,
                          ).copyWith(bottom: AppSpacing.xxl),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final isWide = constraints.maxWidth >= 860;

                              if (isWide) {
                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      flex: 5,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _buildHeroPhoto(isDesktopWide: true),
                                          if (_dayEntry != null &&
                                              _dayEntry!.photos.length > 1) ...[
                                            const SizedBox(
                                              height: AppSpacing.sm,
                                            ),
                                            _buildMultiPhotoStrip(),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: AppSpacing.xl),
                                    Expanded(
                                      flex: 4,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 250,
                                            ),
                                            child: _isEditing
                                                ? _buildEditForm()
                                                : _buildMetadataCard(),
                                          ),
                                          if (!_isEditing) ...[
                                            const SizedBox(
                                              height: AppSpacing.lg,
                                            ),
                                            _buildActionButtons(),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Hero Photo Container
                                  _buildHeroPhoto(),

                                  // Multi-Photo Carousel Strip
                                  if (_dayEntry != null &&
                                      _dayEntry!.photos.length > 1) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    _buildMultiPhotoStrip(),
                                  ],

                                  const SizedBox(height: AppSpacing.md),

                                  // Information Card or Edit Form
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 250),
                                    child: _isEditing
                                        ? _buildEditForm()
                                        : _buildMetadataCard(),
                                  ),

                                  const SizedBox(height: AppSpacing.lg),

                                  // Action Buttons
                                  if (!_isEditing) _buildActionButtons(),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Minimal Header with back button, date display, and edit toggle
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.pageHorizontal,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Circular Back Button
          Semantics(
            label: 'Back to journal',
            button: true,
            child: Tooltip(
              message: 'Back',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (_isEditing && _hasUnsavedChanges) {
                    final shouldDiscard = await _onWillPop();
                    if (!shouldDiscard) return;
                  }
                  if (mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 48.0,
                    minHeight: 48.0,
                  ),
                  child: Center(
                    child: Container(
                      width: 40.0,
                      height: 40.0,
                      decoration: BoxDecoration(
                        color: AppColors.surfaceSubtle,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20.0,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Date / Context Title
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isEditing ? 'Edit Memory' : 'Photo Memory',
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 1.0),
                  Text(
                    _formatShortDate(_currentEntry.date),
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // Action: Cancel in Edit Mode, or Browse/Edit in View Mode
          if (_isEditing)
            Semantics(
              label: 'Cancel editing',
              button: true,
              child: Tooltip(
                message: 'Cancel',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _cancelEditMode,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 48.0,
                      minHeight: 48.0,
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14.0,
                          vertical: 8.0,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(16.0),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Add photo to this date',
                  button: true,
                  child: Tooltip(
                    message: 'Add Photo',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _addPhotoToDay,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 48.0,
                          minHeight: 48.0,
                        ),
                        child: Center(
                          child: Container(
                            width: 40.0,
                            height: 40.0,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.add_a_photo_outlined,
                              size: 18.0,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Semantics(
                  label: 'Browse recorded days',
                  button: true,
                  child: Tooltip(
                    message: 'Browse Days',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openSwipeDays,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 48.0,
                          minHeight: 48.0,
                        ),
                        child: Center(
                          child: Container(
                            width: 40.0,
                            height: 40.0,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.view_carousel_rounded,
                              size: 19.0,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Semantics(
                  label: 'Edit memory details',
                  button: true,
                  child: Tooltip(
                    message: 'Edit',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _enterEditMode,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minWidth: 48.0,
                          minHeight: 48.0,
                        ),
                        child: Center(
                          child: Container(
                            width: 40.0,
                            height: 40.0,
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.edit_outlined,
                              size: 18.0,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Horizontal multi-photo thumbnail strip with intra-day photo switching and reordering
  Widget _buildMultiPhotoStrip() {
    final photos = _dayEntry!.photos;
    final currentIndex = photos.indexWhere(
      (p) => p.effectiveId == _currentEntry.effectiveId,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Photos on this day (${currentIndex >= 0 ? currentIndex + 1 : 1} of ${photos.length})',
                style: TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Semantics(
                    button: true,
                    label: 'Reorder photos',
                    child: InkWell(
                      onTap: _showReorderDialog,
                      borderRadius: BorderRadius.circular(6.0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.swap_vert_rounded,
                              size: 14.0,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 2.0),
                            Text(
                              'Reorder',
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Semantics(
                    button: true,
                    label: 'Add another photo',
                    child: InkWell(
                      onTap: _addPhotoToDay,
                      borderRadius: BorderRadius.circular(6.0),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6.0,
                          vertical: 2.0,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_rounded,
                              size: 14.0,
                              color: AppColors.accent,
                            ),
                            const SizedBox(width: 2.0),
                            Text(
                              'Add',
                              style: TextStyle(
                                fontSize: 11.0,
                                fontWeight: FontWeight.w700,
                                color: AppColors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 52.0,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) {
                final photo = photos[index];
                final isSelected =
                    photo.effectiveId == _currentEntry.effectiveId;
                return Semantics(
                  button: true,
                  selected: isSelected,
                  label: 'Switch to photo ${index + 1}',
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _currentEntry = photo;
                        if (!_isEditing) {
                          _titleController.text = photo.title;
                          _locationController.text = photo.location ?? '';
                        }
                      });
                      if (_heroPageController.hasClients &&
                          _heroPageController.page?.round() != index) {
                        _heroPageController.animateToPage(
                          index,
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                        );
                      }
                    },
                    child: Container(
                      width: 52.0,
                      height: 52.0,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.accent
                              : AppColors.border,
                          width: isSelected ? 2.2 : 0.8,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6.5),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            (photo.hasRealImage && photo.isImageFileAvailable)
                                ? Image.file(
                                    File(photo.imagePath!),
                                    cacheWidth: 140,
                                    cacheHeight: 140,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _buildFallbackThumbnail(photo),
                                  )
                                : _buildFallbackThumbnail(photo),
                            Positioned(
                              bottom: 2.0,
                              right: 2.0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3.5,
                                  vertical: 0.5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(3.0),
                                ),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 8.0,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Prominent Hero Photo Container
  Widget _buildHeroPhoto({bool isDesktopWide = false}) {
    final hasMultiple = _dayEntry != null && _dayEntry!.photos.length > 1;
    final double heroHeight;
    if (isDesktopWide) {
      heroHeight = 440.0;
    } else {
      heroHeight = _isEditing ? 180.0 : 380.0;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: double.infinity,
      height: heroHeight,
      decoration: const BoxDecoration(
        borderRadius: AppRadii.card,
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadii.card,
        child: hasMultiple
            ? PageView.builder(
                controller: _heroPageController,
                physics: const BouncingScrollPhysics(),
                itemCount: _dayEntry!.photos.length,
                onPageChanged: (index) {
                  final photo = _dayEntry!.photos[index];
                  setState(() {
                    _currentEntry = photo;
                    if (!_isEditing) {
                      _titleController.text = photo.title;
                      _locationController.text = photo.location ?? '';
                    }
                  });
                },
                itemBuilder: (context, index) {
                  final photo = _dayEntry!.photos[index];
                  return _buildHeroPhotoCard(
                    photo,
                    index: index,
                    totalPhotos: _dayEntry!.photos.length,
                  );
                },
              )
            : _buildHeroPhotoCard(_currentEntry, index: 0, totalPhotos: 1),
      ),
    );
  }

  Widget _buildHeroPhotoCard(
    PhotoEntry photo, {
    required int index,
    required int totalPhotos,
  }) {
    final heroSemanticLabel = photo.title.trim().isNotEmpty
        ? 'Photo memory: ${photo.title.trim()}'
        : 'Photo memory captured on ${_formatDate(photo.date)}';

    return Semantics(
      image: true,
      label: heroSemanticLabel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Photo Content
          if (photo.hasRealImage && photo.isImageFileAvailable)
            Image.file(
              File(photo.imagePath!),
              cacheWidth: 1440,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  _buildFallbackArt(photo),
            )
          else
            _buildFallbackArt(photo),

          // Vignette Shading
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Colors.transparent,
                  Color(0x66000000),
                ],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Category Badge Top-Left & Position Indicator
          Positioned(
            top: 14.0,
            left: 14.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10.0,
                    vertical: 4.5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.wb_sunny_rounded,
                        size: 12.0,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4.0),
                      Text(
                        photo.category,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                if (totalPhotos > 1) ...[
                  const SizedBox(width: 6.0),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 4.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      '${index + 1} of $totalPhotos',
                      style: const TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Time Badge Bottom-Left
          Positioned(
            bottom: 14.0,
            left: 14.0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10.0,
                vertical: 4.5,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 12.0,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4.0),
                  Text(
                    photo.timeFormatted,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackArt([PhotoEntry? photo]) {
    final entry = photo ?? _currentEntry;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: entry.gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          entry.icon,
          size: _isEditing ? 48.0 : 72.0,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _buildFallbackThumbnail(PhotoEntry photo) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: photo.gradientColors,
        ),
      ),
      child: Center(child: Icon(photo.icon, size: 20.0, color: Colors.white)),
    );
  }

  /// Normal Mode: Rich Diary Metadata Display Card
  Widget _buildMetadataCard() {
    final hasTitle = _currentEntry.title.trim().isNotEmpty;
    final hasLocation =
        _currentEntry.location != null &&
        _currentEntry.location!.trim().isNotEmpty;
    final hasTime = _currentEntry.timeFormatted.trim().isNotEmpty;
    final note = _dayEntry?.note.trim() ?? '';

    return Container(
      key: const ValueKey('metadata_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Diary Date & Time Header Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today_rounded,
                      size: 13.0,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 5.0),
                    Expanded(
                      child: Text(
                        _formatDate(_currentEntry.date),
                        style: TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (hasTime)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 12.0,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 4.0),
                    Text(
                      _currentEntry.timeFormatted,
                      style: AppTypography.caption.copyWith(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // Title Section
          if (hasTitle) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _currentEntry.title.trim(),
              style: TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
          ],

          // Location Byline
          if (hasLocation) ...[
            const SizedBox(height: 8.0),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14.0,
                  color: AppColors.accent,
                ),
                const SizedBox(width: 4.0),
                Expanded(
                  child: Text(
                    _currentEntry.location!.trim(),
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.0,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // Daily Note Section (Shared across all photos for this date)
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.surfaceSubtle,
              borderRadius: BorderRadius.circular(10.0),
              border: Border.all(color: AppColors.border, width: 0.6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notes_rounded,
                      size: 15.0,
                      color: AppColors.accent,
                    ),
                    const SizedBox(width: 5.0),
                    Text(
                      'DAILY NOTE',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accent,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4.0),
                Text(
                  note.isNotEmpty
                      ? note
                      : 'No reflection written for this day yet.',
                  style: TextStyle(
                    fontSize: 13.0,
                    fontStyle: note.isNotEmpty
                        ? FontStyle.normal
                        : FontStyle.italic,
                    color: note.isNotEmpty
                        ? AppColors.textPrimary
                        : AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.md),
          Divider(height: 1.0, color: AppColors.borderSubtle),
          const SizedBox(height: AppSpacing.md),

          // Local Storage Status Section
          _buildStorageStatusSection(),
        ],
      ),
    );
  }

  /// Local storage status presentation section
  Widget _buildStorageStatusSection() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: AppColors.border, width: 0.8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sd_storage_outlined,
            size: 18.0,
            color: AppColors.statIconBlueGrey,
          ),
          const SizedBox(width: 10.0),
          Expanded(
            child: Semantics(
              label: 'Photo saved locally on device',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Stored Locally on Device',
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    'Private & offline • Kept in your personal diary storage',
                    style: TextStyle(
                      fontSize: 11.0,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Edit Mode Form
  Widget _buildEditForm() {
    return Container(
      key: const ValueKey('edit_form'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.card,
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'DIARY ENTRY',
                style: TextStyle(
                  fontSize: 11.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                _formatShortDate(_currentEntry.date),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Title Input with character limit (max 80)
          _buildFormField(
            label: 'Title',
            controller: _titleController,
            hintText: 'Enter photo title',
            maxLength: 80,
            textInputAction: TextInputAction.next,
          ),

          const SizedBox(height: AppSpacing.md),

          // Location Input with character limit (max 100)
          _buildFormField(
            label: 'Location',
            controller: _locationController,
            hintText: 'e.g. Echo Park Lake',
            prefixIcon: Icons.location_on_outlined,
            maxLength: 100,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.streetAddress,
          ),

          const SizedBox(height: AppSpacing.md),

          // Shared Daily Note Input
          _buildFormField(
            label: 'Daily Note',
            controller: _noteController,
            hintText: 'Write a reflection or note for this day...',
            minLines: 3,
            maxLines: 5,
            maxLength: 500,
            prefixIcon: Icons.notes_rounded,
            textInputAction: TextInputAction.newline,
            keyboardType: TextInputType.multiline,
          ),

          const SizedBox(height: AppSpacing.lg),

          // Save & Cancel Buttons
          Row(
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  label: 'Save memory changes',
                  child: ElevatedButton.icon(
                    onPressed: _saveChanges,
                    icon: const Icon(Icons.check_rounded, size: 16.0),
                    label: const Text('Save Changes'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryButtonBackground,
                      foregroundColor: AppColors.primaryButtonForeground,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12.0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.0),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Semantics(
                button: true,
                label: 'Cancel editing',
                child: OutlinedButton(
                  onPressed: _cancelEditMode,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12.0,
                      horizontal: 16.0,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    int minLines = 1,
    int maxLines = 1,
    int? maxLength,
    IconData? prefixIcon,
    TextInputAction? textInputAction,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (maxLength != null)
              AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final currentLength = controller.text.length;
                  return Text(
                    '$currentLength/$maxLength',
                    style: TextStyle(
                      fontSize: 11.0,
                      color: currentLength > maxLength
                          ? AppColors.error
                          : AppColors.textMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 6.0),
        TextFormField(
          controller: controller,
          minLines: minLines,
          maxLines: maxLines,
          maxLength: maxLength,
          buildCounter:
              (
                context, {
                required currentLength,
                required isFocused,
                maxLength,
              }) => null,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          style: TextStyle(
            fontSize: 14.0,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 13.5, color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceSubtle,
            prefixIcon: prefixIcon != null
                ? Icon(prefixIcon, size: 18.0, color: AppColors.accent)
                : null,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 10.0,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide(color: AppColors.textPrimary, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  /// Action Buttons Row (Add, Replace, Browse, Edit, Share, Delete)
  Widget _buildActionButtons() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Add another photo to this day',
                child: ElevatedButton.icon(
                  onPressed: _addPhotoToDay,
                  icon: const Icon(Icons.add_a_photo_outlined, size: 16.0),
                  label: const Text('Add Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryButtonBackground,
                    foregroundColor: AppColors.primaryButtonForeground,
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    minimumSize: const Size(0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                button: true,
                label: 'Replace current photo',
                child: OutlinedButton.icon(
                  onPressed: _replaceCurrentPhoto,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16.0),
                  label: const Text('Replace Photo'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    minimumSize: const Size(0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            button: true,
            label: 'Browse recorded days',
            child: OutlinedButton.icon(
              onPressed: _openSwipeDays,
              icon: const Icon(Icons.view_carousel_rounded, size: 16.0),
              label: const Text('Browse Days'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                minimumSize: const Size(double.infinity, 48.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                label: 'Edit memory details',
                child: OutlinedButton.icon(
                  onPressed: _enterEditMode,
                  icon: const Icon(Icons.edit_outlined, size: 16.0),
                  label: const Text('Edit Memory'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    minimumSize: const Size(0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Semantics(
                button: true,
                label: 'Share memory',
                child: OutlinedButton.icon(
                  onPressed: _triggerMockShare,
                  icon: const Icon(Icons.share_outlined, size: 16.0),
                  label: const Text('Share'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12.0),
                    minimumSize: const Size(0, 48.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: Semantics(
            button: true,
            label: 'Delete memory from your daily journal',
            child: OutlinedButton.icon(
              onPressed: _showDeleteConfirmationDialog,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 16.0,
                color: Colors.red.shade700,
              ),
              label: Text(
                'Delete Memory',
                style: TextStyle(color: Colors.red.shade700),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.red.shade200),
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                minimumSize: const Size(double.infinity, 48.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[date.weekday - 1]}, ${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String _formatShortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
