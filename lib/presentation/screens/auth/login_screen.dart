/// لاگ ان اسکرین
/// Login Screen — Supabase Email/Password Authentication
///
/// There is deliberately NO self-registration here: user accounts are created
/// by institution provisioning / invitation only. New users are directed to
/// contact their institution administrator. Post-login navigation follows
/// [postAuthDestination] (platform admins go directly to the platform
/// console; everyone else follows [AuthRoute] from the auth provider).
///
/// VISUAL ONLY: the m360 input/button language and [showM360SnackBar]
/// feedback. Auth logic, routing conditions and provider calls are
/// byte-for-byte identical to before.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/constants/app_typography.dart';
import '../../../core/design/m360.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/loading_widget.dart';
import '../../../providers/auth_provider.dart';
import 'auth_routing.dart';
import 'forgot_password_screen.dart';

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
  bool _rememberMe = true;
  bool _obscurePassword = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    // Restore the "remember me" choice and the remembered e-mail (never the
    // password) so returning users don't retype everything.
    _rememberMe =
        StorageService.getBool(kRememberMeKey, defaultValue: true) ?? true;
    final rememberedEmail = StorageService.getString(kRememberedEmailKey);
    if (rememberedEmail != null && rememberedEmail.isNotEmpty) {
      _emailController.text = rememberedEmail;
    }
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
    ).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOut));

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
      showM360SnackBar(context, errorMsg, isError: true);
      return;
    }

    // Persist the "remember me" choice; the e-mail is remembered for
    // pre-fill, the password is never stored — the Supabase session (or
    // the OS password manager via autofill) handles that.
    await StorageService.saveBool(kRememberMeKey, _rememberMe);
    if (_rememberMe) {
      await StorageService.saveString(
          kRememberedEmailKey, _emailController.text.trim());
    } else {
      await StorageService.remove(kRememberedEmailKey);
    }

    // Route per the provider's post-login decision, shared with AuthGate:
    // platform admins go directly to the platform console.
    final destination = postAuthDestination(ref.read(authProvider));
    if (destination == null || !mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => destination),
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
                    // Groups the e-mail + password fields so the OS password
                    // manager can offer saved credentials (autofillHints).
                    child: AutofillGroup(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          // Logo & App Name
                          _buildHeader(),
                          const SizedBox(height: 48),
                          // Login Card — constrained so it doesn't stretch
                          // edge-to-edge on wide desktops.
                          M360ConstrainedWidth(
                            maxWidth: 480,
                            child: _buildLoginCard(),
                          ),
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
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // App logo — the real brand mark, presented as an app-icon tile
        // with a soft light ring so it sits proudly on the gradient.
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 3,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(25),
            child: Image.asset(
              'assets/images/app_logo.png',
              width: 112,
              height: 112,
              fit: BoxFit.cover,
              // A missing or unbundled asset must never break the login
              // screen: fall back to a branded mark (teal tile with 360 in
              // Nastaleeq) — never a generic mosque icon.
              errorBuilder: (context, error, stackTrace) => Container(
                width: 112,
                height: 112,
                color: AppColors.primary,
                child: Center(
                  child: Text(
                    '360',
                    style: AppTypography.labelNastaliq.copyWith(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
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
          style: AppTypography.labelNastaliq.copyWith(
            color: Colors.white70,
            fontSize: 18,
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
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          _buildEmailInput(),
          const SizedBox(height: 16),

          // Password Input
          _buildPasswordInput(),
          const SizedBox(height: 8),

          // Forgot password link
          Align(
            alignment: Alignment.centerLeft,
            child: M360TertiaryButton(
              label: 'پاس ورڈ بھول گئے؟',
              onPressed: _openForgotPassword,
            ),
          ),

          // Remember me — controls whether the session survives app restarts
          // (see the "Remember me" contract in providers/auth_provider.dart).
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                activeColor: AppColors.primary,
                onChanged: (value) {
                  setState(() => _rememberMe = value ?? true);
                },
              ),
              // Expanded: the Nastaleeq label must wrap instead of pushing
              // the Row 8px past the card at 360px.
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _rememberMe = !_rememberMe),
                  child: Text(
                    'مجھے یاد رکھیں',
                    style: AppTypography.labelNastaliq.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Login Button — the single primary CTA (orange).
          M360PrimaryButton(
            label: AppStrings.loginButton,
            icon: Icons.arrow_back,
            fullWidth: true,
            isLoading: _isLoading,
            onPressed: _isLoading ? null : _handleLogin,
          ),
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
    // m360 field language (Nastaleeq label + hint, teal focus ring) while
    // keeping autofillHints + validator identical.
    return TextFormField(
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      autocorrect: false,
      autofillHints: const [AutofillHints.email],
      style: AppTypography.bodyLarge,
      decoration: m360FieldDecoration(
        label: 'ای میل',
        hint: 'اپنا ای میل درج کریں',
        prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary),
      ),
      validator: (value) => Validators.email(value),
    );
  }

  Widget _buildPasswordInput() {
    final tooltip = _obscurePassword ? 'پاس ورڈ دکھائیں' : 'پاس ورڈ چھپائیں';
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      textAlign: TextAlign.right,
      textDirection: TextDirection.rtl,
      autofillHints: const [AutofillHints.password],
      onEditingComplete: () => TextInput.finishAutofillContext(),
      style: AppTypography.bodyLarge,
      decoration: m360FieldDecoration(
        label: 'پاس ورڈ',
        hint: 'اپنا پاس ورڈ درج کریں',
        prefixIcon: const Icon(Icons.lock, color: AppColors.primary),
        // Show/hide toggle — passwords are long and typos are the
        // most common login failure.
        suffixIcon: IconButton(
          tooltip: tooltip,
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: AppColors.textSecondary,
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      validator: (value) => Validators.required(value, fieldName: 'پاس ورڈ'),
    );
  }

  Widget _buildFooter() {
    // Neutral product credit (tenant identity is runtime-driven).
    return Text(
      'Madrasa 360',
      style: AppTypography.bodySmall.copyWith(
        color: Colors.white54,
        letterSpacing: 0.5,
      ),
    );
  }
}
