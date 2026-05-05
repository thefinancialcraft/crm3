import 'package:shared_preferences/shared_preferences.dart';
import 'logger_service.dart';

class ConsentService {
  static const String _hasAcceptedConsentKey = 'has_accepted_consent';
  
  static Future<bool> hasUserAcceptedConsent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hasAcceptedConsentKey) ?? false;
    } catch (e) {
      LoggerService.warn('Failed to check consent status: $e');
      return false;
    }
  }
  
  static Future<void> markConsentAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasAcceptedConsentKey, true);
      LoggerService.info('User consent marked as accepted');
    } catch (e) {
      LoggerService.warn('Failed to save consent status: $e');
    }
  }

  static const String _hasFinishedOnboardingKey = 'has_finished_onboarding';
  
  static Future<bool> hasFinishedOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_hasFinishedOnboardingKey) ?? false;
    } catch (e) {
      return false;
    }
  }
  
  static Future<void> markOnboardingComplete() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_hasFinishedOnboardingKey, true);
    } catch (e) {
      LoggerService.warn('Failed to save onboarding status: $e');
    }
  }
}