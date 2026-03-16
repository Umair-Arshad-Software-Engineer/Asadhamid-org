import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';

import '../Provider/lanprovider.dart';

class PasswordChangeDialog extends StatefulWidget {
  const PasswordChangeDialog({Key? key}) : super(key: key);

  @override
  _PasswordChangeDialogState createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends State<PasswordChangeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No user logged in');

      // Re-authenticate user (required for sensitive operations)
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: _currentPasswordController.text,
      );

      await user.reauthenticateWithCredential(credential);

      // Change password
      await user.updatePassword(_newPasswordController.text);

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Provider.of<LanguageProvider>(context, listen: false).isEnglish
                  ? 'Password changed successfully!'
                  : 'پاس ورڈ کامیابی سے تبدیل ہو گیا!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      if (e.code == 'wrong-password') {
        errorMessage = Provider.of<LanguageProvider>(context, listen: false).isEnglish
            ? 'Current password is incorrect'
            : 'موجودہ پاس ورڈ غلط ہے';
      } else if (e.code == 'weak-password') {
        errorMessage = Provider.of<LanguageProvider>(context, listen: false).isEnglish
            ? 'New password is too weak'
            : 'نیا پاس ورڈ بہت کمزور ہے';
      } else {
        errorMessage = e.message ?? 'Error changing password';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final isEnglish = languageProvider.isEnglish;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isEnglish ? 'Change Password' : 'پاس ورڈ تبدیل کریں',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade800,
                ),
              ),
              SizedBox(height: 20),

              // Current Password
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: isEnglish ? 'Current Password' : 'موجودہ پاس ورڈ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCurrent ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return isEnglish ? 'Please enter current password' : 'براہ کرم موجودہ پاس ورڈ درج کریں';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // New Password
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: isEnglish ? 'New Password' : 'نیا پاس ورڈ',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return isEnglish ? 'Please enter new password' : 'براہ کرم نیا پاس ورڈ درج کریں';
                  }
                  if (value.length < 6) {
                    return isEnglish ? 'Password must be at least 6 characters' : 'پاس ورڈ کم از کم 6 حروف کا ہونا چاہیے';
                  }
                  return null;
                },
              ),
              SizedBox(height: 16),

              // Confirm Password
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: isEnglish ? 'Confirm New Password' : 'نئے پاس ورڈ کی تصدیق کریں',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return isEnglish ? 'Please confirm new password' : 'براہ کرم نئے پاس ورڈ کی تصدیق کریں';
                  }
                  if (value != _newPasswordController.text) {
                    return isEnglish ? 'Passwords do not match' : 'پاس ورڈ مماثل نہیں ہیں';
                  }
                  return null;
                },
              ),
              SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _isLoading ? null : () => Navigator.pop(context),
                      child: Text(
                        isEnglish ? 'Cancel' : 'منسوخ کریں',
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _changePassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade400,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Text(isEnglish ? 'Change Password' : 'پاس ورڈ تبدیل کریں'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}