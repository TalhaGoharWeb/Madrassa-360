import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../providers/auth_provider.dart';
import '../main_screen.dart';
import 'forgot_password_screen.dart';
import 'no_access_screen.dart';
import 'tenant_picker_screen.dart';

/// لاگ ان اسکرین
/// Login Screen — Supabase Email/Password Authentication
///
/// There is deliberately NO self-registration here: user accounts are created
/// by institution provisioning / invitation only. New users are directed to
/// contact their institution administrator. Post-login navigation follows
/// [AuthRoute] from the auth provider (home / tenantPicker / noAccess).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final success = await ref.read(authProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!success) {
      // Error message is already in authProvider.state.errorMessage
      final errorMsg =
          ref.read(authProvider).errorMessage ?? 'لاگ ان میں خرابی';
      ErrorHandler.showErrorSnackBar(context, errorMsg);
      return;
    }

    // Route per the provider's post-login decision.
    final route = ref.read(authProvider).route;
    Widget? destination;
    switch (route) {
      case AuthRoute.home:
        destination = const MainScreen();
        break;
      case AuthRoute.tenantPicker:
        destination = const TenantPickerScreen();
        break;
      case AuthRoute.noAccess:
        destination = const NoAccessScreen();
        break;
      case AuthRoute.login:
        destination = null; // shouldn't happen after a successful login
        break;
    }
    if (destination == null || !mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination!),
    );
  }

  void _openForgotPassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LoadingOverlay(
        isLoading: _isLoading,
        message: 'لاگ ان ہو رہا ہے...',
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.primary,
                AppColors.primaryDark,
              ],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        // Logo & App Name
                        _buildHeader(),
                        const SizedBox(height: 48),
                        // Login Card
                        _buildLoginCard(),
                        const SizedBox(height: 24),
                        // Footer
                        _buildFooter(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Logo Container
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.mosque,
              size: 50,
              color: AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // App Name
        Text(
          AppStrings.appName,
          style: AppTypography.headingLarge.copyWith(
            color: Colors.white,
            fontSize: 36,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppStrings.appTagline,
          style: AppTypography.bodyMedium.copyWith(
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Center(
            child: Text(
              'داخلہ',
              style: AppTypography.headingSmall,
            ),
          ),
          const SizedBox(height: 24),

          // Email Input
          Text(
            'ای میل',
            style: AppTypography.labelLarge,
          ),
          const SizedBox(height: 8),
          _buildEmailInput(),
          const SizedBox(height: 16),

          // Password Input
          Text(
            'پاس ورڈ',
            style: AppTypography.labelLarge,
          ),
          const SizedBox(height: 8),
          _buildPasswordInput(),
          const SizedBox(height: 8),

          // Forgot password link
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _openForgotPassword,
              child: Text(
                'پاس ورڈ بھول گئے؟',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Login Button
          _buildLoginButton(),
          const SizedBox(height: 16),

          // No self-registration: accounts are provisioned by the institution.
          Center(
            child: Text(
              'اکاؤنٹ نہیں ہے؟ اپنے ادارے کے منتظم سے رابطہ کریں',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailInput() {
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textAlign: TextAlign.right,
      autocorrect: false,
      style: AppTypography.bodyLarge,
      decoration: InputDecoration(
        hintText: 'اپنا ای میل درج کریں',
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary.withOpacity(0.5),
        ),
        prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      validator: (value) => Validators.email(value),
    );
  }

  Widget _buildPasswordInput() {
    return TextFormField(
      controller: _passwordController,
      obscureText: true,
      textAlign: TextAlign.right,
      style: AppTypography.bodyLarge,
      decoration: InputDecoration(
        hintText: 'اپنا پاس ورڈ درج کریں',
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.textSecondary.withOpacity(0.5),
        ),
        prefixIcon: const Icon(Icons.lock, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
      ),
      validator: (value) => Validators.required(value, fieldName: 'پاس ورڈ'),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: AppColors.primary.withOpacity(0.4),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.loginButton,
                    style: AppTypography.titleMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_back, size: 20),
                ],
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return Text(
      'Developed by HijaziApps',
      style: AppTypography.bodySmall.copyWith(
        color: Colors.white54,
        letterSpacing: 0.5,
      ),
    );
  }
}
