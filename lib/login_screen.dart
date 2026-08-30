import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/app_constants.dart';
import 'core/app_theme.dart';
import 'dashboard_screen.dart';
import 'registration_screen.dart';
import 'public_request_screen.dart';
import 'important_files_screen.dart';
import 'admin_command_center_screen.dart';
import 'hr_dashboard_screen.dart';
import 'procurement_dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = true;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  Future<void> _checkExistingLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? email = prefs.getString(AppConstants.keyUserEmail);
      final bool isAdmin = prefs.getBool(AppConstants.keyIsAdmin) ?? false;
      
      if (email != null && email.isNotEmpty && mounted) {
        if (isAdmin || email.toLowerCase() == AppConstants.adminEmail.toLowerCase()) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => AdminCommandCenterScreen(userEmail: email)),
          );
        } else if (prefs.getBool('is_procurement') == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => ProcurementDashboardScreen(userEmail: email)),
          );
        } else if (prefs.getBool('is_hr') == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HrDashboardScreen(userEmail: email)),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => DashboardScreen(userEmail: email)),
          );
        }
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    final input = _emailController.text.trim().toLowerCase();
    if (input.isEmpty) {
      _showError("Wprowadź login lub email.");
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (input == AppConstants.adminEmail || input == 'admin') {
        await _saveAndNavigate(AppConstants.adminEmail, true);
        return;
      }

      QuerySnapshot query = await FirebaseFirestore.instance
          .collection('employees')
          .where(Filter.or(
            Filter('email', isEqualTo: input),
            Filter('login', isEqualTo: input)
          ))
          .get();

      if (query.docs.isNotEmpty) {
        final userDoc = query.docs.first;
        final userData = userDoc.data() as Map<String, dynamic>;
        final String email = userData['email'] ?? input;
        final String? storedPassword = userData['password'];
        final bool forceReset = userData['forcePasswordReset'] ?? false;

        if (userData['isActive'] == true) {
          // Check password if it exists in DB
          if (storedPassword != null && storedPassword.isNotEmpty) {
            if (_passwordController.text != storedPassword) {
              _showError("Błędne hasło.");
              return;
            }
          }

          if (forceReset) {
            _showPasswordResetDialog(userDoc.id);
            return;
          }

          final String pos = (userData['position'] ?? '').toString().toLowerCase();
          final bool isHr = (userData['permissions'] ?? {})['access_hr_pulpit'] == true || 
                            pos.contains('księgow') || pos.contains('kadry');
          final bool isProcurement = (userData['permissions'] ?? {})['access_procurement_pulpit'] == true ||
                                     pos.contains('zaopatrz');
          
          await _saveAndNavigate(email, pos == 'administrator', isHr: isHr, isProcurement: isProcurement);
        } else {
          _showError("Twoje konto oczekuje na aktywację.");
        }
      } else {
        // Legacy fallback or direct ID check
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('employees').doc(input).get();
        if (doc.exists) {
          final userData = doc.data() as Map<String, dynamic>;
          final String? storedPassword = userData['password'];
          final bool forceReset = userData['forcePasswordReset'] ?? false;

          if (userData['isActive'] == true) {
            if (storedPassword != null && storedPassword.isNotEmpty) {
              if (_passwordController.text != storedPassword) {
                _showError("Błędne hasło.");
                return;
              }
            }

            if (forceReset) {
              _showPasswordResetDialog(doc.id);
              return;
            }

            final String pos = (userData['position'] ?? '').toString().toLowerCase();
            final bool isHr = (userData['permissions'] ?? {})['access_hr_pulpit'] == true || 
                              pos.contains('księgow') || pos.contains('kadry');
            final bool isProcurement = (userData['permissions'] ?? {})['access_procurement_pulpit'] == true ||
                                       pos.contains('zaopatrz');
            
            await _saveAndNavigate(input, pos == 'administrator', isHr: isHr, isProcurement: isProcurement);
          } else {
            _showError("Konto nieaktywne.");
          }
        } else {
          _showError("Nie znaleziono użytkownika.");
        }
      }
    } catch (e) {
      _showError("Błąd: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showPasswordResetDialog(String docId) {
    final newPassCtrl = TextEditingController();
    final confirmPassCtrl = TextEditingController();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppTheme.primaryNavy, width: 2)),
        title: const Text("WYMAGANA ZMIANA HASŁA", style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("To Twoje pierwsze logowanie lub administrator zresetował Twoje hasło. Wprowadź nowe hasło.", style: TextStyle(fontSize: 12)),
            const SizedBox(height: 20),
            TextField(controller: newPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Nowe hasło", border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: confirmPassCtrl, obscureText: true, decoration: const InputDecoration(labelText: "Powtórz nowe hasło", border: OutlineInputBorder())),
            if (isSaving) const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: isSaving ? null : () async {
              if (newPassCtrl.text.length < 4) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Hasło musi mieć min. 4 znaki.")));
                return;
              }
              if (newPassCtrl.text != confirmPassCtrl.text) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Hasła nie są identyczne.")));
                return;
              }

              setDS(() => isSaving = true);
              await FirebaseFirestore.instance.collection('employees').doc(docId).update({
                'password': newPassCtrl.text,
                'forcePasswordReset': false,
              });
              
              Navigator.pop(ctx);
              _handleLogin(); // Retry login with new credentials
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryNavy, foregroundColor: Colors.white),
            child: const Text("ZAPISZ HASŁO I ZALOGUJ"),
          )
        ],
      )),
    );
  }

  Future<void> _saveAndNavigate(String email, bool isAdmin, {bool isHr = false, bool isProcurement = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyUserEmail, email);
    await prefs.setBool(AppConstants.keyIsAdmin, isAdmin);
    await prefs.setBool('is_hr', isHr);
    await prefs.setBool('is_procurement', isProcurement);
    
    // Explicitly reload to ensure persistence on Web
    await prefs.reload();

    if (mounted) {
      if (isAdmin || email.toLowerCase() == AppConstants.adminEmail.toLowerCase()) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => AdminCommandCenterScreen(userEmail: email)),
        );
      } else if (isProcurement) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => ProcurementDashboardScreen(userEmail: email)),
        );
      } else if (isHr) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HrDashboardScreen(userEmail: email)),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DashboardScreen(userEmail: email)),
        );
      }
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(backgroundColor: theme.scaffoldBackgroundColor, body: const Center(child: CircularProgressIndicator(color: Color(0xFF007BFF))));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(40.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF001A2C) : Colors.white, 
                    borderRadius: BorderRadius.circular(24), 
                    boxShadow: isDark ? null : [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]
                  ),
                  child: Image.asset('assets/logo.png', height: 100, fit: BoxFit.contain, filterQuality: FilterQuality.high),
                ),
                const SizedBox(height: 32),
                Text(AppConstants.appName, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface, letterSpacing: -1)),
                const Text("ES CRM • PROFESSIONAL EDITION", style: TextStyle(color: Color(0xFF007BFF), fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 48),
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        controller: _emailController,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: "Login / Email",
                          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                          prefixIcon: Icon(Icons.person_outline, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                          filled: true, fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.withOpacity(0.1))),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        autofillHints: const [AutofillHints.password],
                        obscureText: _obscurePassword,
                        style: TextStyle(color: theme.colorScheme.onSurface),
                        decoration: InputDecoration(
                          labelText: "Hasło",
                          labelStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5)),
                          prefixIcon: Icon(Icons.lock_outline, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                          suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.5)), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
                          filled: true, fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: isDark ? Colors.white10 : Colors.grey.withOpacity(0.1))),
                        ),
                        onSubmitted: (_) => _handleLogin(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _handleLogin,
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF001A2C), foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 2),
                  child: const Text("ZALOGUJ SIĘ", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PublicRequestScreen())),
                  icon: const Icon(Icons.calculate_outlined),
                  label: const Text("ZAPYTAJ O WYCENĘ", style: TextStyle(fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange, width: 2),
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegistrationScreen())), child: Text("Rejestracja nowego pracownika", style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
