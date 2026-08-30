import 'dart:io';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:flutter/material.dart';

class EmailResult {
  final bool success;
  final String message;
  EmailResult(this.success, this.message);
}

class EmailService {
  static Future<EmailResult> sendEmailWithAttachment({
    required String recipient,
    required String subject,
    required String body,
    required String filePath,
    required String fileName,
  }) async {
    if (kIsWeb) return EmailResult(false, "Funkcja niedostępna w przeglądarce.");
    return await _send(recipient: recipient, subject: subject, body: body, filePath: filePath, fileName: fileName);
  }

  static Future<EmailResult> sendTestEmail() async {
    if (kIsWeb) return EmailResult(false, "Funkcja niedostępna w przeglądarce.");
    
    final prefs = await SharedPreferences.getInstance();
    final String? smtpJson = prefs.getString('smtp_settings');
    if (smtpJson == null) return EmailResult(false, "Brak konfiguracji SMTP.");
    final settings = json.decode(smtpJson);
    final String user = settings['user']?.toString().trim() ?? '';
    
    return await _send(
      recipient: user,
      subject: 'ES Manager - Test Połączenia',
      body: 'Test wysyłki z dnia: ${DateTime.now()}',
    );
  }

  static Future<EmailResult> _send({
    required String recipient,
    required String subject,
    required String body,
    String? filePath,
    String? fileName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? smtpJson = prefs.getString('smtp_settings');
      if (smtpJson == null) return EmailResult(false, "Skonfiguruj pocztę w ustawieniach.");
      
      final settings = json.decode(smtpJson);
      final String host = settings['server']?.toString().trim() ?? '';
      final int port = int.tryParse(settings['port']?.toString() ?? '465') ?? 465;
      final String user = settings['user']?.toString().trim() ?? '';
      final String pass = settings['pass']?.toString().trim() ?? '';

      if (host.isEmpty || user.isEmpty || pass.isEmpty) return EmailResult(false, "Uzupełnij wszystkie pola poczty.");

      // KLUCZOWA ZMIANA: Używamy bezpośredniego SmtpServer z właściwym szyfrowaniem
      // Dla portu 465 (Interia/Gmail) SSL musi być TRUE od samego początku.
      final smtpServer = SmtpServer(
        host,
        port: port,
        username: user,
        password: pass,
        ssl: true, // Wymuszamy SSL dla 465
        ignoreBadCertificate: true,
      );

      final message = Message()
        ..from = Address(user, 'ES Manager')
        ..recipients.add(recipient)
        ..subject = subject
        ..text = body;

      if (filePath != null && fileName != null) {
        message.attachments.add(FileAttachment(File(filePath))..fileName = fileName);
      }

      await send(message, smtpServer).timeout(const Duration(seconds: 20));
      return EmailResult(true, "Wysłano pomyślnie!");
    } catch (e) {
      debugPrint('SMTP error: $e');
      String msg = e.toString();
      if (msg.contains('535')) msg = "Błędny login lub hasło (535).";
      if (msg.contains('Connection refused')) msg = "Serwer odrzucił połączenie. Sprawdź czy suwak 'Program pocztowy' na int.pl jest włączony.";
      return EmailResult(false, msg);
    }
  }

  static Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('smtp_settings');
  }
}
