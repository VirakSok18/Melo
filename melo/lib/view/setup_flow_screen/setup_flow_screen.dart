import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import 'username_step.dart';
import 'profile_picture_step.dart';
import 'genre_step.dart';
import 'artist_step.dart';
import '../loading_screen/loading_screen.dart';
import '../../main.dart';

class SetupFlowScreen extends StatefulWidget {
  const SetupFlowScreen({super.key});

  @override
  State<SetupFlowScreen> createState() => _SetupFlowScreenState();
}

class _SetupFlowScreenState extends State<SetupFlowScreen> {
  int _currentStep = 0;
  bool _showLoading = false;

  final Set<String> _selectedGenres = {};
  String? _username;
  String? _displayName;
  File? _pickedImage;
  String? _selectedAvatar;

  void _onGenresSelected(Set<String> genres) {
    _selectedGenres.clear();
    _selectedGenres.addAll(genres);
  }

  void _nextStep() {
    if (_currentStep < 3) {
      setState(() => _currentStep++);
    } else {
      setState(() => _showLoading = true);
    }
  }

  void _loadingComplete() {
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
      AuthService().signOut();
    }
  }

  Widget _buildStep() {
    switch (_currentStep) {
      case 0:
        return UsernameStep(
          key: const ValueKey('username_step'),
          initialUsername: _username,
          initialDisplayName: _displayName,
          onContinue: _nextStep,
          onUsernameChanged: (u) => _username = u,
          onDisplayNameChanged: (d) => _displayName = d,
        );
      case 1:
        return ProfilePictureStep(
          key: const ValueKey('profile_picture_step'),
          initialPickedImage: _pickedImage,
          initialSelectedAvatar: _selectedAvatar,
          onContinue: _nextStep,
          onBack: _previousStep,
          onImageChanged: (img) => _pickedImage = img,
          onAvatarChanged: (av) => _selectedAvatar = av,
        );
      case 2:
        return GenreStep(
          key: const ValueKey('genre_step'),
          initialSelectedGenres: _selectedGenres,
          onContinue: _nextStep,
          onBack: _previousStep,
          onGenresSelected: _onGenresSelected,
        );
      case 3:
      default:
        return ArtistStep(
          key: const ValueKey('artist_step'),
          selectedGenres: _selectedGenres,
          username: _username,
          displayName: _displayName,
          pickedImage: _pickedImage,
          selectedAvatar: _selectedAvatar,
          onContinue: _nextStep,
          onBack: _previousStep,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showLoading) {
      return LoadingScreen(onComplete: _loadingComplete);
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF191919),
      body: _buildStep(),
    );
  }
}
