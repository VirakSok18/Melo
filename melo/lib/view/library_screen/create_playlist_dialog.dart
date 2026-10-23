import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class CreatePlaylistBottomSheet extends StatefulWidget {
  final Future<void> Function(String name, String? coverImage, bool isPublic)
      onCreated;
  final bool isCollaborative;

  const CreatePlaylistBottomSheet({
    super.key,
    required this.onCreated,
    this.isCollaborative = false,
  });

  static Future<void> show({
    required BuildContext context,
    required Future<void> Function(
            String name, String? coverImage, bool isPublic)
        onCreated,
    bool isCollaborative = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreatePlaylistBottomSheet(
        onCreated: onCreated,
        isCollaborative: isCollaborative,
      ),
    );
  }

  @override
  State<CreatePlaylistBottomSheet> createState() =>
      _CreatePlaylistBottomSheetState();
}

class _CreatePlaylistBottomSheetState extends State<CreatePlaylistBottomSheet> {
  final TextEditingController _nameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  String? _coverPath;
  bool _isPublic = true;
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF2A2A2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Choose cover image',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF514AED)),
                title: const Text('Camera',
                    style:
                        TextStyle(color: Colors.white, fontFamily: 'Poppins')),
                onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
              ),
              ListTile(
                leading:
                    const Icon(Icons.photo_library, color: Color(0xFF514AED)),
                title: const Text('Gallery',
                    style:
                        TextStyle(color: Colors.white, fontFamily: 'Poppins')),
                onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source != null) {
      final image = await _picker.pickImage(
          source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
      if (image == null) return;

      try {
        final CroppedFile? cropped = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: 'Crop Cover',
              toolbarColor: const Color(0xFF191919),
              toolbarWidgetColor: Colors.white,
              backgroundColor: const Color(0xFF191919),
              activeControlsWidgetColor: const Color(0xFF514AED),
              initAspectRatio: CropAspectRatioPreset.square,
              lockAspectRatio: true,
            ),
            IOSUiSettings(
              title: 'Crop Cover',
              aspectRatioLockEnabled: true,
              resetAspectRatioEnabled: false,
            ),
          ],
        );

        if (cropped != null && mounted) {
          setState(() => _coverPath = cropped.path);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _coverPath = image.path);
        }
      }
    }
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a playlist name');
      return;
    }
    if (_creating) return;

    setState(() {
      _creating = true;
      _error = null;
    });

    try {
      Navigator.of(context).pop();
      await widget.onCreated(name, _coverPath, _isPublic);
    } catch (e) {
      debugPrint('Create playlist error: $e');
      if (mounted) {
        setState(() {
          _error = 'Failed to create playlist. Please try again.';
          _creating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: 24 + bottomInset,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.isCollaborative ? 'New Collaboration' : 'New Playlist',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        color: Colors.white70, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: Stack(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: _coverPath == null
                            ? const Color(0xFF514AED).withValues(alpha: 0.15)
                            : null,
                        image: _coverPath != null
                            ? DecorationImage(
                                image: FileImage(File(_coverPath!)),
                                fit: BoxFit.cover,
                              )
                            : null,
                        border: Border.all(
                          color: _coverPath == null
                              ? const Color(0xFF514AED).withValues(alpha: 0.3)
                              : Colors.transparent,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _coverPath == null
                          ? Center(
                              child: Icon(
                                widget.isCollaborative
                                    ? Icons.group_work_rounded
                                    : Icons.queue_music_rounded,
                                size: 48,
                                color: const Color(0xFF817BFF),
                              ),
                            )
                          : null,
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF514AED),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: const Color(0xFF1E1E1E), width: 3),
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _coverPath != null ? 'Change Cover' : 'Add Cover Image',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 12,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Playlist Name',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Poppins',
                fontSize: 15,
              ),
              decoration: InputDecoration(
                hintText: 'Enter playlist title...',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontFamily: 'Poppins',
                  fontSize: 14,
                ),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide:
                      const BorderSide(color: Color(0xFF514AED), width: 1.5),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  _isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
                  size: 15,
                  color: _isPublic
                      ? const Color(0xFF817BFF)
                      : Colors.white.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 6),
                Text(
                  _isPublic ? 'Public' : 'Private',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 12,
                    fontFamily: 'Poppins',
                  ),
                ),
                const Spacer(),
                Transform.scale(
                  scale: 0.75,
                  child: Switch.adaptive(
                    value: _isPublic,
                    activeTrackColor: const Color(0xFF514AED),
                    onChanged: (val) => setState(() => _isPublic = val),
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFFF4D4D),
                  fontSize: 12,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _creating ? null : _create,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF514AED),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _creating
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        widget.isCollaborative
                            ? 'Create Collaboration'
                            : 'Create Playlist',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Poppins',
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Backwards compatibility alias
typedef CreatePlaylistDialog = CreatePlaylistBottomSheet;
