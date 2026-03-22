import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/screens/tenant_main_screen.dart';
import 'package:pinput/pinput.dart';
import '../service/auth_service.dart';
import '../main.dart'; // Для перехода на MapScreen

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _authService = AuthService();

  // Контроллеры формы
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _innController = TextEditingController();
  final _phoneController = TextEditingController();

  String _selectedRole = 'TENANT'; // По умолчанию арендатор
  bool _isLoading = false;

  final Color _primaryOrange = const Color(0xFFFF8C00);

  // --- Логика регистрации ---
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
      // Если регистрация успешна, открываем шторку с кодом
      _showVerificationSheet(email);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка регистрации. Возможно, email уже занят.'), backgroundColor: Colors.red),
      );
    }
  }

  // --- Мини-окошко (Bottom Sheet) для ввода кода ---
  void _showVerificationSheet(String email) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // Нельзя закрыть просто свайпом вниз
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return VerificationBottomSheet(
          email: email,
          authService: _authService,
          primaryOrange: _primaryOrange,
          onEmailEditTap: () {
            Navigator.pop(context); // Закрываем шторку, возвращаемся к форме
          },
          onVerified: () {
            // Код верный! Закрываем шторку и переходим на карту
            Navigator.pop(context);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const TenantMainScreen()),
            );
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Create an account',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // Выбор роли
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'TENANT', label: Text('Ищу площадь')),
                    ButtonSegment(value: 'LANDLORD', label: Text('Сдаю площадь')),
                  ],
                  selected: {_selectedRole},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() => _selectedRole = newSelection.first);
                  },
                  style: ButtonStyle(
                    backgroundColor: MaterialStateProperty.resolveWith((states) {
                      if (states.contains(MaterialState.selected)) return _primaryOrange.withOpacity(0.2);
                      return Colors.white;
                    }),
                    iconColor: MaterialStateProperty.all(_primaryOrange),
                  ),
                ),
                const SizedBox(height: 20),

                // Поля ввода
                _buildTextField(_nameController, Icons.business, 'ФИО или Название компании'),
                const SizedBox(height: 16),
                _buildTextField(_innController, Icons.numbers, 'ИНН', isNumber: true),
                const SizedBox(height: 16),
                _buildTextField(_phoneController, Icons.phone, 'Телефон', isNumber: true),
                const SizedBox(height: 16),
                _buildTextField(_emailController, Icons.email, 'Email'),
                const SizedBox(height: 16),
                _buildTextField(_passwordController, Icons.lock, 'Password', isObscure: true),
                const SizedBox(height: 30),

                // Кнопка регистрации
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleRegister,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Sign up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Вспомогательный метод для красивых инпутов
  Widget _buildTextField(TextEditingController controller, IconData icon, String hint, {bool isObscure = false, bool isNumber = false}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.black54),
        hintText: hint,
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.black12)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.black)),
      ),
    );
  }
}

// --- Отдельный виджет для шторки (чтобы таймер обновлялся без перерисовки всей формы) ---
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
  int _secondsLeft = 120; // 2 минуты
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
    // Стили для ячеек Pinput
    final defaultPinTheme = PinTheme(
      width: 50,
      height: 60,
      textStyle: const TextStyle(fontSize: 24, color: Colors.black, fontWeight: FontWeight.bold),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black26),
        borderRadius: BorderRadius.circular(8),
      ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom, // Поднимает шторку над клавиатурой
        left: 24,
        right: 24,
        top: 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Check your email',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a 6-digit code to',
            style: TextStyle(color: Colors.grey[600], fontSize: 16),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                widget.email,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              IconButton(
                icon: Icon(Icons.edit, color: widget.primaryOrange, size: 20),
                onPressed: widget.onEmailEditTap, // Кнопка исправления почты
              )
            ],
          ),
          const SizedBox(height: 24),

          // Те самые 6 ячеек
          _isVerifying
              ? const CircularProgressIndicator()
              : Pinput(
            length: 6,
            controller: _pinController,
            defaultPinTheme: defaultPinTheme,
            focusedPinTheme: defaultPinTheme.copyDecorationWith(
              border: Border.all(color: widget.primaryOrange, width: 2),
            ),
            onCompleted: _verifyCode, // Автоматически проверяет, когда введено 6 цифр
          ),

          const SizedBox(height: 32),

          // Таймер или кнопка повторной отправки
          _secondsLeft > 0
              ? Text(
            'Resend code in ${_secondsLeft ~/ 60}:${(_secondsLeft % 60).toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          )
              : TextButton(
            onPressed: _resendCode,
            child: Text(
              'Resend Code',
              style: TextStyle(color: widget.primaryOrange, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}