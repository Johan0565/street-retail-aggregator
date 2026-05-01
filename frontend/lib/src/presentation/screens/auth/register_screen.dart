import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import '../../../services/auth_service.dart';
import '../landlord/LandlordMainScreen.dart';
import '../tenant/tenant_main_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  final _authService = AuthService();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _innController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedRole = 'TENANT';
  bool _isLoading = false;
  bool _obscurePassword = true;

  final Color _primaryOrange = const Color(0xFFFF8C00);

  late AnimationController _animController;
  late Animation<Offset> _contentSlide;
  late Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _contentSlide = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _contentFade = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _animController.forward();
  }

  Future<void> _handleRegister() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заполните обязательные поля')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final success = await _authService.register(
      email,
      _passwordController.text.trim(),
      _selectedRole,
      _nameController.text.trim(),
      _innController.text.trim(),
      _phoneController.text.trim(),
    );

    setState(() => _isLoading = false);

    if (success) {
      _showVerificationSheet(email);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка регистрации. Возможно, email уже занят.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showVerificationSheet(String email) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return VerificationBottomSheet(
          email: email,
          authService: _authService,
          primaryOrange: _primaryOrange,
          onEmailEditTap: () => Navigator.pop(context),
          onVerified: () async {
            final role = await _authService.getUserRole();
            if (!context.mounted) return;
            Navigator.pop(context);
            if (role == 'LANDLORD') {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const LandlordMainScreen()),
              );
            } else {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const TenantMainScreen()),
              );
            }
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 8),
          child: FadeTransition(
            opacity: _contentFade,
            child: SlideTransition(
              position: _contentSlide,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Create account',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Зарегистрируйтесь, чтобы начать',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),

                  // Custom role selector
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      children: [
                        _buildRoleTab('TENANT', 'Ищу площадь'),
                        _buildRoleTab('LANDLORD', 'Сдаю площадь'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  _buildField(_nameController, Icons.person_outline_rounded, 'ФИО или Название компании'),
                  const SizedBox(height: 14),
                  _buildField(_innController, Icons.badge_outlined, 'ИНН', isNumber: true),
                  const SizedBox(height: 14),
                  _buildField(_phoneController, Icons.phone_outlined, 'Телефон', isNumber: true),
                  const SizedBox(height: 14),
                  _buildField(_emailController, Icons.email_outlined, 'Email'),
                  const SizedBox(height: 14),
                  _buildField(
                    _passwordController,
                    Icons.lock_outline_rounded,
                    'Пароль',
                    isObscure: _obscurePassword,
                    hasVisibilityToggle: true,
                  ),
                  const SizedBox(height: 32),

                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryOrange,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _primaryOrange.withValues(alpha: 0.6),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isLoading
                          ? const SizedBox(
                              key: ValueKey('loading'),
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                            )
                          : const Text(
                              key: ValueKey('text'),
                              'Sign up',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.3,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleTab(String role, String label) {
    final isSelected = _selectedRole == role;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedRole = role),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected ? _primaryOrange : Colors.grey.shade500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    IconData icon,
    String hint, {
    bool isObscure = false,
    bool isNumber = false,
    bool hasVisibilityToggle = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
        suffixIcon: hasVisibilityToggle
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.grey.shade400,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _primaryOrange, width: 1.5),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _innController.dispose();
    _phoneController.dispose();
    super.dispose();
  }
}

class VerificationBottomSheet extends StatefulWidget {
  final String email;
  final AuthService authService;
  final Color primaryOrange;
  final VoidCallback onEmailEditTap;
  final VoidCallback onVerified;

  const VerificationBottomSheet({
    super.key,
    required this.email,
    required this.authService,
    required this.primaryOrange,
    required this.onEmailEditTap,
    required this.onVerified,
  });

  @override
  State<VerificationBottomSheet> createState() => _VerificationBottomSheetState();
}

class _VerificationBottomSheetState extends State<VerificationBottomSheet> {
  int _secondsLeft = 120;
  Timer? _timer;
  bool _isVerifying = false;
  final _pinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    setState(() => _secondsLeft = 120);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _verifyCode(String code) async {
    setState(() => _isVerifying = true);
    final success = await widget.authService.verifyEmail(widget.email, code);
    setState(() => _isVerifying = false);

    if (success) {
      widget.onVerified();
    } else {
      _pinController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный код'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _resendCode() async {
    final success = await widget.authService.resendCode(widget.email);
    if (success) {
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Новый код отправлен'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultPinTheme = PinTheme(
      width: 52,
      height: 58,
      textStyle: const TextStyle(fontSize: 22, color: Colors.black, fontWeight: FontWeight.bold),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 28,
        right: 28,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icon
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: widget.primaryOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.email_outlined, color: widget.primaryOrange, size: 28),
          ),
          const SizedBox(height: 16),

          const Text(
            'Check your email',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a 6-digit code to',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.email,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              GestureDetector(
                onTap: widget.onEmailEditTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.edit_outlined, color: widget.primaryOrange, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          _isVerifying
              ? CircularProgressIndicator(color: widget.primaryOrange)
              : Pinput(
                  length: 6,
                  controller: _pinController,
                  defaultPinTheme: defaultPinTheme,
                  focusedPinTheme: defaultPinTheme.copyDecorationWith(
                    border: Border.all(color: widget.primaryOrange, width: 2),
                    color: widget.primaryOrange.withValues(alpha: 0.05),
                  ),
                  submittedPinTheme: defaultPinTheme.copyDecorationWith(
                    border: Border.all(color: widget.primaryOrange.withValues(alpha: 0.5)),
                    color: widget.primaryOrange.withValues(alpha: 0.05),
                  ),
                  onCompleted: _verifyCode,
                ),

          const SizedBox(height: 28),

          _secondsLeft > 0
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Text(
                      'Resend in ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ],
                )
              : TextButton(
                  onPressed: _resendCode,
                  child: Text(
                    'Resend Code',
                    style: TextStyle(
                      color: widget.primaryOrange,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
