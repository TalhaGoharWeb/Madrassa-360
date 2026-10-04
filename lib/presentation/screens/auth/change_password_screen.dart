/// پاس ورڈ تبدیل کریں
/// Change Password — for signed-in users.
///
/// Unlike the forgot-password recovery flow, this works with the current
/// session: the user enters a new password (twice) and it is applied via
/// [AuthRepository.updatePassword]. Accessible from Profile → Account.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../data/repositories/auth_repository.dart';
import '../../../providers/auth_provider.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
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

  Future<void> _changePassword() async {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const M360AppBar(title: 'پاس ورڈ تبدیل کریں'),
      backgroundColor: AppColors.background,
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: 'پاس ورڈ تبدیل کیا جا رہا ہے...',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _done ? _buildDone() : _buildForm(),
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
            const Icon(Icons.lock_outline, size: 72, color: AppColors.primary),
            const SizedBox(height: 24),
            Text(
              'اپنا نیا پاس ورڈ درج کریں۔ کم از کم 6 حروف ہونا ضروری ہے۔',
              style: AppTypography.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscureNew,
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.bodyLarge,
              decoration: m360FieldDecoration(
                label: 'نیا پاس ورڈ',
                hint: 'نیا پاس ورڈ درج کریں',
                prefixIcon:
                    const Icon(Icons.lock_outlined, color: AppColors.primary),
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
              textAlign: TextAlign.right,
              textDirection: TextDirection.rtl,
              autocorrect: false,
              enableSuggestions: false,
              style: AppTypography.bodyLarge,
              decoration: m360FieldDecoration(
                label: 'پاس ورڈ کی تصدیق',
                hint: 'نیا پاس ورڈ دوبارہ درج کریں',
                prefixIcon:
                    const Icon(Icons.lock_outlined, color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.primary,
                  ),
                  onPressed: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'تصدیق ضروری ہے';
                if (v != _passwordController.text) {
                  return 'پاس ورڈ آپس میں نہیں ملتے';
                }
                return null;
              },
            ),
            const SizedBox(height: 32),
            M360PrimaryButton(
              label: 'پاس ورڈ تبدیل کریں',
              icon: Icons.check_circle_outline,
              fullWidth: true,
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _changePassword,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDone() {
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
            'آپ کا پاس ورڈ کامیابی سے تبدیل کر دیا گیا ہے۔',
            style: AppTypography.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          M360SecondaryButton(
            label: 'واپس جائیں',
            icon: Icons.arrow_forward,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
