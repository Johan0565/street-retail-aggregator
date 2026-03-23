import 'package:flutter/material.dart';
import 'package:frontend/screens/tenant_main_screen.dart';
import '../service/auth_service.dart';
import '../main.dart'; // Если MapScreen лежит в main.dart
import 'LandlordMainScreen.dart';
import 'register_screen.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _isLoading = false;
  final AuthService _authService = AuthService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  // Загружаем почту, если пользователь ранее ставил галочку
  Future<void> _loadSavedData() async {
    final savedEmail = await _authService.getSavedEmail();
    if (savedEmail != null) {
      setState(() {
        _emailController.text = savedEmail;
        _rememberMe = true;
      });
    }
  }
  // Функция обработки логина
  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите email и пароль')),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Дергаем бэкенд
    final success = await _authService.login(email, password, _rememberMe);

    if (!mounted) return; // Проверка, что экран еще открыт
    setState(() => _isLoading = false);

    if (success) {
      // Читаем сохраненную роль
      final role = await _authService.getUserRole();
      if (!mounted) return;

      // Маршрутизация на основе роли
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
    } else {
      // Ошибка
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Неверный email или пароль. Попробуйте снова.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Логотип
                Image.asset(
                  'assets/Logo.png',
                  height: 150,
                ),
                const SizedBox(height: 40),

                // 2. Заголовок
                const Text(
                  'Sign in',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),

                // 3. Поле Email
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person, color: Colors.black),
                    hintText: 'Email',
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black12),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 4. Поле Password
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.lock, color: Colors.black),
                    hintText: 'Password',
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black12),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.black),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 5. Чекбокс "Remember me"
                Row(
                  children: [
                    Checkbox(
                      value: _rememberMe,
                      activeColor: _primaryOrange,
                      onChanged: (value) {
                        setState(() {
                          _rememberMe = value ?? false;
                        });
                      },
                    ),
                    const Text(
                      'Remember me',
                      style: TextStyle(color: Colors.black87),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // 6. Оранжевая кнопка "Log in"
            ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin, // Отключаем кнопку во время загрузки
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              )
                  : const Text(
                'Log in',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 20),

            // 7. Кнопка "Create an account"
            TextButton(
              onPressed: () {
                // Переход на экран регистрации
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RegisterScreen()),
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.black54,
              ),
              child: const Text(
                'Create an account',
                style: TextStyle(
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}