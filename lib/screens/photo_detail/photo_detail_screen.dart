import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_per_day/core/constants/app_constants.dart';
import 'package:photo_per_day/core/theme/app_colors.dart';
import 'package:photo_per_day/core/theme/app_radii.dart';
import 'package:photo_per_day/core/theme/app_shadows.dart';
import 'package:photo_per_day/core/theme/app_spacing.dart';
import 'package:photo_per_day/core/theme/app_typography.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';
import 'package:photo_per_day/data/models/sync_presentation_model.dart';
import 'package:photo_per_day/data/services/persistent_daily_photo_store.dart';
import 'package:photo_per_day/data/services/sync_coordinator.dart';
import 'package:photo_per_day/data/services/sync_worker.dart';

/// Dedicated Photo Detail Screen for viewing, editing, and managing a single photo memory.
///
/// Features a dominant hero photo view, rich metadata presentation, local edit mode
/// with responsive form inputs, mock share action, and a destructive delete confirmation modal.
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
  late PhotoEntry _currentEntry;
  bool _isEditing = false;

  late final TextEditingController _titleController;
  late final TextEditingController _captionController;
  late final TextEditingController _locationController;

  @override
  void initState() {
    super.initState();
    _currentEntry =
        PersistentDailyPhotoStore.instance.getPhoto(widget.photoEntry.date) ??
        widget.photoEntry;
    _titleController = TextEditingController(text: _currentEntry.title);
    _captionController = TextEditingController(
      text: _currentEntry.caption ?? '',
    );
    _locationController = TextEditingController(
      text: _currentEntry.location ?? '',
    );
    PersistentDailyPhotoStore.instance.addListener(_onPhotoStoreUpdated);
    SyncWorker.instance.addListener(_onPhotoStoreUpdated);
    SyncCoordinator.instance.addListener(_onPhotoStoreUpdated);
  }

  void _onPhotoStoreUpdated() {
    if (!mounted) return;
    final updated = PersistentDailyPhotoStore.instance.getPhoto(
      _currentEntry.date,
    );
    if (updated != null) {
      setState(() {
        _currentEntry = updated;
        if (!_isEditing) {
          _titleController.text = updated.title;
          _captionController.text = updated.caption ?? '';
          _locationController.text = updated.location ?? '';
        }
      });
    }
  }

  @override
  void dispose() {
    PersistentDailyPhotoStore.instance.removeListener(_onPhotoStoreUpdated);
    SyncWorker.instance.removeListener(_onPhotoStoreUpdated);
    SyncCoordinator.instance.removeListener(_onPhotoStoreUpdated);
    _titleController.dispose();
    _captionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  void _openSwipeDays() {
    Navigator.of(
      context,
    ).pushNamed(AppConstants.swipeDaysRoute, arguments: _currentEntry.dateKey);
  }

  void _enterEditMode() {
    setState(() {
      _titleController.text = _currentEntry.title;
      _captionController.text = _currentEntry.caption ?? '';
      _locationController.text = _currentEntry.location ?? '';
      _isEditing = true;
    });
  }

  /// Whether the user has modified any diary field since entering edit mode.
  bool get _hasUnsavedChanges {
    final currentTitle = _titleController.text.trim();
    final currentCaption = _captionController.text.trim();
    final currentLocation = _locationController.text.trim();

    final originalTitle = _currentEntry.title.trim();
    final originalCaption = (_currentEntry.caption ?? '').trim();
    final originalLocation = (_currentEntry.location ?? '').trim();

    return currentTitle != originalTitle ||
        currentCaption != originalCaption ||
        currentLocation != originalLocation;
  }

  /// Prompts the user before discarding unsaved edits.
  Future<bool> _onWillPop() async {
    if (!_isEditing || !_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: AppRadii.dialogRadius,
          side: BorderSide(color: AppColors.border, width: 0.8),
        ),
        title: const Text(
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
            child: const Text(
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
      _captionController.text = _currentEntry.caption ?? '';
      _locationController.text = _currentEntry.location ?? '';
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

    final rawCaption = _captionController.text.trim();
    final updatedCaption = rawCaption.isEmpty ? null : rawCaption;
    final clearCaption = rawCaption.isEmpty;

    final rawLocation = _locationController.text.trim();
    final updatedLocation = rawLocation.isEmpty ? null : rawLocation;
    final clearLocation = rawLocation.isEmpty;

    try {
      final updated = await PersistentDailyPhotoStore.instance
          .updatePhotoMetadata(
            dateKey: _currentEntry.dateKey,
            title: updatedTitle,
            caption: updatedCaption,
            clearCaption: clearCaption,
            location: updatedLocation,
            clearLocation: clearLocation,
          );

      if (mounted) {
        setState(() {
          _currentEntry = updated;
          _isEditing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memory updated successfully!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      // If the photo was a seeded entry not yet in store, fallback to setPhoto
      final fallbackEntry = _currentEntry.copyWith(
        title: updatedTitle,
        caption: updatedCaption,
        clearCaption: clearCaption,
        location: updatedLocation,
        clearLocation: clearLocation,
      );
      PersistentDailyPhotoStore.instance.setPhoto(fallbackEntry);

      if (mounted) {
        setState(() {
          _currentEntry = fallbackEntry;
          _isEditing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Memory updated successfully!'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _triggerMockShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Sharing "${_currentEntry.title}"... (Mock UI)'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showDeleteConfirmationDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadii.dialogRadius,
            side: BorderSide(color: AppColors.border, width: 0.8),
          ),
          title: const Text(
            'Delete this memory?',
            style: TextStyle(
              fontSize: 18.0,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Are you sure you want to remove this photo from your daily journal? This action cannot be undone.',
            style: AppTypography.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 12.0,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(
                'Keep Memory',
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
        );
      },
    );

    if (confirmed == true && mounted) {
      try {
        await PersistentDailyPhotoStore.instance.removePhotoAsync(
          _currentEntry.date,
        );
        widget.onDeleteConfirmed?.call();
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Memory deleted.'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
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
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: Column(
              children: [
                // Minimal Detail Header
                _buildHeader(),

                // Scrollable Detail Content
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.pageHorizontal,
                      AppSpacing.xs,
                      AppSpacing.pageHorizontal,
                      AppSpacing.xxl,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Hero Photo Container
                        _buildHeroPhoto(),

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
                    ),
                  ),
                ),
              ],
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
                    final shouldPop = await _onWillPop();
                    if (shouldPop && mounted) {
                      Navigator.of(context).pop();
                    }
                  } else {
                    Navigator.of(context).pop();
                  }
                },
                child: Container(
                  width: 40.0,
                  height: 40.0,
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    size: 20.0,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),

          // Date / Context Title
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isEditing ? 'Edit Memory' : 'Photo Memory',
                style: const TextStyle(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 1.0),
              Text(
                _formatDate(_currentEntry.date),
                style: const TextStyle(
                  fontSize: 12.0,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),

          // Header Right Action (Edit shortcut or Cancel)
          if (_isEditing)
            Semantics(
              label: 'Cancel editing',
              button: true,
              child: Tooltip(
                message: 'Cancel',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _cancelEditMode,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12.0,
                      vertical: 6.0,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(16.0),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Text(
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
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'Browse recorded days',
                  button: true,
                  child: Tooltip(
                    message: 'Browse Days',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _openSwipeDays,
                      child: Container(
                        width: 40.0,
                        height: 40.0,
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.view_carousel_rounded,
                          size: 19.0,
                          color: AppColors.textPrimary,
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
                      child: Container(
                        width: 40.0,
                        height: 40.0,
                        decoration: const BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          size: 18.0,
                          color: AppColors.textPrimary,
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

  /// Prominent Hero Photo Container
  Widget _buildHeroPhoto() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: double.infinity,
      height: _isEditing ? 180.0 : 380.0,
      decoration: const BoxDecoration(
        borderRadius: AppRadii.card,
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: AppRadii.card,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo Content (Real Image or Gradient Art fallback)
            if (_currentEntry.hasRealImage &&
                _currentEntry.isImageFileAvailable)
              Image.file(
                File(_currentEntry.imagePath!),
                cacheWidth: 1440,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallbackArt(),
              )
            else
              _buildFallbackArt(),

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

            // Category Badge Top-Left
            Positioned(
              top: 14.0,
              left: 14.0,
              child: Container(
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
                      _currentEntry.category,
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
                      _currentEntry.timeFormatted,
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
      ),
    );
  }

  Widget _buildFallbackArt() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _currentEntry.gradientColors,
        ),
      ),
      child: Center(
        child: Icon(
          _currentEntry.icon,
          size: _isEditing ? 48.0 : 72.0,
          color: Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  /// Normal Mode: Rich Diary Metadata Display Card
  Widget _buildMetadataCard() {
    final hasTitle = _currentEntry.title.trim().isNotEmpty;
    final hasCaption =
        _currentEntry.caption != null &&
        _currentEntry.caption!.trim().isNotEmpty;
    final hasLocation =
        _currentEntry.location != null &&
        _currentEntry.location!.trim().isNotEmpty;
    final hasTime = _currentEntry.timeFormatted.trim().isNotEmpty;

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
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today_rounded,
                    size: 13.0,
                    color: AppColors.accent,
                  ),
                  const SizedBox(width: 5.0),
                  Text(
                    _formatDate(_currentEntry.date),
                    style: const TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              if (hasTime)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
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

          // Title Section (omitted if empty)
          if (hasTitle) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _currentEntry.title.trim(),
              style: const TextStyle(
                fontSize: 20.0,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
                height: 1.25,
              ),
            ),
          ],

          // Caption Section (omitted if empty)
          if (hasCaption) ...[
            const SizedBox(height: 10.0),
            Text(
              _currentEntry.caption!.trim(),
              style: AppTypography.body.copyWith(
                color: AppColors.textPrimary.withValues(alpha: 0.85),
                height: 1.5,
                fontSize: 14.0,
              ),
            ),
          ],

          // Location Byline (omitted if empty)
          if (hasLocation) ...[
            const SizedBox(height: 12.0),
            Row(
              children: [
                const Icon(
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

          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1.0, color: AppColors.borderSubtle),
          const SizedBox(height: AppSpacing.md),

          // Cloud Backup Status Section
          _buildSyncStatusSection(),
        ],
      ),
    );
  }

  /// Cloud Backup Status presentation section
  Widget _buildSyncStatusSection() {
    final presentation = PhotoSyncPresentation.forEntry(_currentEntry);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: presentation.isFailed
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.border,
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          if (presentation.isBackingUp)
            const SizedBox(
              width: 16.0,
              height: 16.0,
              child: CircularProgressIndicator(
                strokeWidth: 2.0,
                color: AppColors.accent,
              ),
            )
          else
            Icon(presentation.icon, size: 18.0, color: presentation.color),
          const SizedBox(width: 10.0),
          Expanded(
            child: Semantics(
              label: presentation.semanticLabel,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    presentation.detailLabel,
                    style: TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                      color: presentation.isFailed
                          ? AppColors.error
                          : AppColors.textPrimary,
                    ),
                  ),
                  if (presentation.isFailed)
                    const Padding(
                      padding: EdgeInsets.only(top: 2.0),
                      child: Text(
                        'Tap Try Again to retry backup',
                        style: TextStyle(
                          fontSize: 11.0,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (presentation.isFailed)
            Semantics(
              label: 'Try photo backup again',
              button: true,
              child: OutlinedButton(
                onPressed: _handleTryAgain,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 6.0,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0),
                  ),
                ),
                child: const Text(
                  'Try Again',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleTryAgain() async {
    final coordinator = SyncCoordinator.instance;
    if (coordinator.isSyncing) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync is already in progress.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Retrying backup to Google Drive...'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final result = await coordinator.requestSync(trigger: SyncTrigger.manual);
    if (!mounted) return;

    if (result.alreadyRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync is already in progress.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (result.failedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Backup retry failed. Please check connection or Drive settings.',
          ),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
        ),
      );
    } else if (result.succeededCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo backed up successfully!'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
              const Text(
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
                style: const TextStyle(
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

          // Caption Input with character limit (max 1000)
          _buildFormField(
            label: 'Caption / Note',
            controller: _captionController,
            hintText: 'Write a memory or reflection...',
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
          ),

          const SizedBox(height: AppSpacing.md),

          // Location Input with character limit (max 100)
          _buildFormField(
            label: 'Location',
            controller: _locationController,
            hintText: 'e.g. Echo Park Lake',
            prefixIcon: Icons.location_on_outlined,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.streetAddress,
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
                      backgroundColor: AppColors.textPrimary,
                      foregroundColor: Colors.white,
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
                    side: const BorderSide(color: AppColors.border),
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
              style: const TextStyle(
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
          style: const TextStyle(
            fontSize: 14.0,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textMuted,
            ),
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
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: const BorderSide(
                color: AppColors.textPrimary,
                width: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Action Buttons Row (Edit, Share, Delete)
  Widget _buildActionButtons() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _openSwipeDays,
            icon: const Icon(Icons.view_carousel_rounded, size: 16.0),
            label: const Text('Browse Days'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _enterEditMode,
                icon: const Icon(Icons.edit_outlined, size: 16.0),
                label: const Text('Edit Memory'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _triggerMockShare,
                icon: const Icon(Icons.share_outlined, size: 16.0),
                label: const Text('Share'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.0),
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
