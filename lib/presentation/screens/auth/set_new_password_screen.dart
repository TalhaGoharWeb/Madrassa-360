/// نیا پاس ورڈ
/// Set New Password — the second half of the forgot-password flow (SEC-H13).
///
/// Shown by [AuthGate] while [passwordRecoveryModeProvider] is true: the
/// user arrived via a recovery link, the SDK established a recovery
/// session (PASSWORD_RECOVERY), and they must choose a new password before
/// normal routing resumes.
///
/// On success the recovery session is signed out (revoked server-side) and
/// recovery mode ends, landing the user on the login screen to sign in
/// with the new password.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../providers/auth_provider.dart';

class SetNewPasswordScreen extends ConsumerStatefulWidget {
  const SetNewPasswordScreen({super.key});

  @override
  ConsumerState<SetNewPasswordScreen> createState() =>
      _SetNewPasswordScreenState();
}

class _SetNewPasswordScreenState extends ConsumerState<SetNewPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _done = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _setPassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authRepositoryProvider).updatePassword(
            newPassword: _passwordController.text,
          );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _done = true;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showM360SnackBar(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorHandler.logError(e, null);
      showM360SnackBar(context, 'پاس ورڈ تبدیل کرنے میں خرابی', isError: true);
    }
  }

  /// Revoke the recovery session and return to the login screen.
  Future<void> _backToLogin() async {
    try {
      await ref.read(authProvider.notifier).logout();
    } finally {
      ref.read(authProvider.notifier).completePasswordRecovery();
    }
  }

  String? _confirmValidator(String? value) {
    if (value == null || value.isEmpty) return 'پاس ورڈ کی تصدیق ضروری ہے';
    if (value != _passwordController.text) {
      return 'پاس ورڈ مطابق نہیں — دوبارہ لکھیں';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('نیا پاس ورڈ', style: AppTypography.titleLarge),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: 'پاس ورڈ تبدیل کیا جا رہا ہے...',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return M360ConstrainedWidth(
      maxWidth: 480,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.lock_reset, size: 72, color: AppColors.primary),
            const SizedBox(height: 24),
            Text(
              'اپنا نیا پاس ورڈ درج کریں۔',
              style: AppTypography.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscureNew,
              enableSuggestions: false,
              autocorrect: false,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: AppTypography.bodyLarge,
              decoration: m360FieldDecoration(
                label: 'نیا پاس ورڈ',
                hint: 'کم از کم 6 حروف',
                prefixIcon:
                    const Icon(Icons.lock_outline, color: AppColors.primary),
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNew ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.primary,
                  ),
                  onPressed: () => setState(() => _obscureNew = !_obscureNew),
                ),
              ),
              validator: Validators.password,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              enableSuggestions: false,
              autocorrect: false,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              style: AppTypography.bodyLarge,
              decoration: m360FieldDecoration(
                label: 'پاس ورڈ کی تصدیق',
                hint: 'نیا پاس ورڈ دوبارہ لکھیں',
                prefixIcon:
                    const Icon(Icons.lock_outline, color: AppColors.primary),
              ).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.primary,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: _confirmValidator,
            ),
            const SizedBox(height: 32),
            M360PrimaryButton(
              label: 'پاس ورڈ تبدیل کریں',
              icon: Icons.check_circle_outline,
              fullWidth: true,
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _setPassword,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccess() {
    return M360ConstrainedWidth(
      maxWidth: 480,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 48),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 48,
                color: AppColors.success,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'پاس ورڈ تبدیل ہو گیا',
            style: AppTypography.headingSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'آپ کا نیا پاس ورڈ محفوظ کر لیا گیا ہے۔ اب نئے پاس ورڈ سے لاگ ان کریں۔',
            style: AppTypography.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          M360PrimaryButton(
            label: 'لاگ ان پر جائیں',
            icon: Icons.login,
            fullWidth: true,
            onPressed: _backToLogin,
          ),
        ],
      ),
    );
  }
}
