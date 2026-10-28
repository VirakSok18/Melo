import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';

/// Client-side authentication service adapter.
/// Completely decoupled from any external backend server — powered 100% by Supabase Auth.
class ApiService {
  static final AuthService _auth = AuthService();

  static Future<Map<String, dynamic>> sendOtp(String email) async {
    try {
      await _auth.resendSignUpOtp(email: email);
      return {'success': true, 'message': 'Verification code sent to $email'};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Failed to send verification code'};
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
      String email, String code) async {
    try {
      final res = await _auth.verifySignUpOtp(email: email, token: code);
      if (res.user != null) {
        return {'success': true, 'message': 'Verification successful'};
      }
      return {'success': false, 'message': 'Invalid verification code'};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Verification failed. Please try again.'};
    }
  }

  static Future<Map<String, dynamic>> sendForgotPasswordOtp(
      String email) async {
    try {
      await _auth.sendPasswordResetOtp(email);
      return {'success': true, 'message': 'Reset code sent to $email'};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Failed to send reset code'};
    }
  }

  static Future<Map<String, dynamic>> verifyForgotPasswordOtp(
      String email, String code) async {
    try {
      final res = await _auth.verifyPasswordResetOtp(email: email, token: code);
      if (res.user != null) {
        return {'success': true, 'message': 'Code verified successfully'};
      }
      return {'success': false, 'message': 'Invalid verification code'};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Verification failed. Please try again.'};
    }
  }

  static Future<Map<String, dynamic>> resetPassword(
      String email, String code, String newPassword) async {
    try {
      await _auth.updatePassword(newPassword);
      return {'success': true, 'message': 'Password updated successfully'};
    } on AuthException catch (e) {
      return {'success': false, 'message': e.message};
    } catch (e) {
      return {'success': false, 'message': 'Failed to update password'};
    }
  }
}
