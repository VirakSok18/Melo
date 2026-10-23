import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

class ProfilePictureStep extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onBack;
  final ValueChanged<File?> onImageChanged;
  final ValueChanged<String?> onAvatarChanged;
  final File? initialPickedImage;
  final String? initialSelectedAvatar;

  const ProfilePictureStep({
    super.key,
    required this.onContinue,
    required this.onBack,
    required this.onImageChanged,
    required this.onAvatarChanged,
    this.initialPickedImage,
    this.initialSelectedAvatar,
  });

  @override
  State<ProfilePictureStep> createState() => _ProfilePictureStepState();
}

class _ProfilePictureStepState extends State<ProfilePictureStep> {
  final ImagePicker _picker = ImagePicker();
  String? _selectedAvatar;
  File? _pickedImage;

  @override
  void initState() {
    super.initState();
    _pickedImage = widget.initialPickedImage;
    _selectedAvatar = widget.initialSelectedAvatar;
  }

  final List<String> _presetAvatars = [
    'asset/profile_icon_page/Mask group.png',
    'asset/profile_icon_page/Mask group-1.png',
    'asset/profile_icon_page/Mask group-2.png',
    'asset/profile_icon_page/Mask group-3.png',
    'asset/profile_icon_page/Mask group-4.png',
    'asset/profile_icon_page/Mask group-5.png',
    'asset/profile_icon_page/Mask group-6.png',
    'asset/profile_icon_page/Mask group-7.png',
  ];

  Future<void> _pickAndCropImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Photo',
            toolbarColor: const Color(0xFF191919),
            toolbarWidgetColor: Colors.white,
            backgroundColor: const Color(0xFF191919),
            activeControlsWidgetColor: const Color(0xFF514AED),
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Crop Photo',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );

      if (cropped != null && mounted) {
        setState(() {
          _pickedImage = File(cropped.path);
          _selectedAvatar = null;
        });
        widget.onImageChanged(File(cropped.path));
        widget.onAvatarChanged(null);
      }
    } catch (e) {
      debugPrint('Image pick error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 36),
            GestureDetector(
              onTap: widget.onBack,
              child:
                  const Icon(Icons.arrow_back, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 30),
            const Text(
              'Profile picture',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload or select a profile picture',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
                fontFamily: 'Poppins',
              ),
            ),
            const SizedBox(height: 32),
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                GestureDetector(
                  onTap: _pickAndCropImage,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: _pickedImage != null
                        ? ClipOval(
                            child: Image.file(
                              _pickedImage!,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.white.withValues(alpha: 0.4),
                            size: 28,
                          ),
                  ),
                ),
                ..._presetAvatars.map((avatar) {
                  final isSelected =
                      _selectedAvatar == avatar && _pickedImage == null;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedAvatar = avatar;
                        _pickedImage = null;
                      });
                      widget.onImageChanged(null);
                      widget.onAvatarChanged(avatar);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF514AED)
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: ClipOval(
                        child: Image.asset(
                          avatar,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: const Color(0xFF2D2D44),
                              child: const Icon(
                                Icons.person,
                                color: Colors.white38,
                                size: 40,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 40),
            Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(27),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF514AED),
                    Colors.white,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
              child: ElevatedButton(
                onPressed: widget.onContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(27),
                  ),
                ),
                child: const Text(
                  'Continue',
                  style: TextStyle(
                    color: Color(0xFF0D0D0D),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
