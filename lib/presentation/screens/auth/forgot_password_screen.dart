/// پاس ورڈ بھول گئے؟
/// Forgot Password — sends a Supabase password-reset email, then shows
/// a success state. No account recovery beyond the reset link is offered here.
///
/// VISUAL ONLY: the m360 input/button language and [showM360SnackBar]
/// feedback. The reset flow, error handling and logging are unchanged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../providers/auth_provider.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authProvider.notifier)
          .sendPasswordReset(_emailController.text.trim());
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _sent = true;
      });
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showM360SnackBar(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ErrorHandler.logError(e, null);
      showM360SnackBar(context, 'ری سیٹ لنک بھیجنے میں خرابی', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('پاس ورڈ ری سیٹ', style: AppTypography.titleLarge),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: 'ری سیٹ لنک بھیجا جا رہا ہے...',
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _sent ? _buildSuccess() : _buildForm(),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.lock_reset, size: 72, color: AppColors.primary),
          const SizedBox(height: 24),
          Text(
            'اپنا رجسٹرڈ ای میل درج کریں — ہم آپ کو پاس ورڈ ری سیٹ کرنے کا لنک بھیجیں گے۔',
            style: AppTypography.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          // m360 field language (Nastaleeq label + hint, teal focus ring)
          // while keeping keyboard type, direction and validator identical.
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textAlign: TextAlign.right,
            textDirection: TextDirection.rtl,
            autocorrect: false,
            style: AppTypography.bodyLarge,
            decoration: m360FieldDecoration(
              label: 'ای میل',
              hint: 'اپنا ای میل درج کریں',
              prefixIcon:
                  const Icon(Icons.email_outlined, color: AppColors.primary),
            ),
            validator: Validators.email,
          ),
          const SizedBox(height: 32),
          M360PrimaryButton(
            label: 'ری سیٹ لنک بھیجیں',
            icon: Icons.mark_email_read_outlined,
            fullWidth: true,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _sendResetLink,
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 48),
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.mark_email_read,
            size: 48,
            color: AppColors.success,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'ری سیٹ لنک بھیج دیا گیا',
          style: AppTypography.headingSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'اگر یہ ای میل ہمارے ریکارڈ میں موجود ہے تو آپ کو جلد ہی پاس ورڈ ری سیٹ کا لنک موصول ہو جائے گا۔ براہ کرم اپنا ان باکس (اور اسپام فولڈر) چیک کریں۔',
          style: AppTypography.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        M360SecondaryButton(
          label: 'لاگ ان پر واپس جائیں',
          icon: Icons.arrow_forward,
          fullWidth: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
