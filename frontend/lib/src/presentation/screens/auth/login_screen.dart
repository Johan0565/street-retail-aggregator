import 'package:flutter/material.dart';
import '../../../domain/saved_account.dart';
import '../../../services/auth_service.dart';
import '../landlord/LandlordMainScreen.dart';
import '../tenant/tenant_main_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _passwordFocus = FocusNode();
  bool _rememberMe = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  final AuthService _authService = AuthService();
  final Color _primaryOrange = const Color(0xFFFF8C00);

  List<SavedAccount> _savedAccounts = [];
  String? _resumingEmail;

  late AnimationController _animController;
  late Animation<double> _logoScale;
  late Animation<double> _logoFade;
  late Animation<Offset> _contentSlide;
  late Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _logoScale = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.55, curve: Curves.easeOutBack),
      ),
    );
    _logoFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );
    _contentSlide = Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
      ),
    );
    _contentFade = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.25, 0.85, curve: Curves.easeIn),
    );

    _loadSavedData();
    _animController.forward();
  }

  Future<void> _loadSavedData() async {
    final accounts = await _authService.getSavedAccounts();
    final savedEmail = await _authService.getSavedEmail();
    if (!mounted) return;
    setState(() {
      _savedAccounts = accounts;
      if (savedEmail != null && _emailController.text.isEmpty) {
        _emailController.text = savedEmail;
        _rememberMe = true;
      }
    });
  }

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

    final success = await _authService.login(email, password, _rememberMe);

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (success) {
      final role = await _authService.getUserRole();
      if (!mounted) return;
      _navigateToHome(role);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Неверный email или пароль. Попробуйте снова.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToHome(String? role) {
    if (role == 'LANDLORD') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LandlordMainScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TenantMainScreen()),
      );
    }
  }

  Future<void> _handleAccountTap(SavedAccount account) async {
    if (_resumingEmail != null) return;
    setState(() => _resumingEmail = account.email);

    final role = await _authService.resumeSavedAccount(account.email);

    if (!mounted) return;
    setState(() => _resumingEmail = null);

    if (role != null) {
      _navigateToHome(role);
      return;
    }

    // Сессия протухла — переключаем форму на этот аккаунт и просим пароль.
    setState(() {
      _emailController.text = account.email;
      _passwordController.clear();
      _rememberMe = true;
    });
    _passwordFocus.requestFocus();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Войдите заново в ${account.email} — сессия истекла'),
        backgroundColor: _primaryOrange,
      ),
    );
  }

  Future<void> _confirmRemoveAccount(SavedAccount account) async {
    final removed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => _buildAccountSheet(ctx, account),
    );
    if (removed == true) {
      await _authService.removeSavedAccount(account.email);
      await _loadSavedData();
    }
  }

  Widget _buildAccountSheet(BuildContext ctx, SavedAccount account) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _avatar(account, size: 44, fontSize: 16),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.displayName?.isNotEmpty == true
                            ? account.displayName!
                            : account.email,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        account.role == 'LANDLORD' ? 'Арендодатель' : 'Арендатор',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: Colors.red.withValues(alpha: 0.06),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 20),
              label: const Text(
                'Удалить аккаунт из списка',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Отмена'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                FadeTransition(
                  opacity: _logoFade,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Image.asset('assets/Logo.png', height: 130),
                  ),
                ),
                const SizedBox(height: 28),

                FadeTransition(
                  opacity: _contentFade,
                  child: SlideTransition(
                    position: _contentSlide,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Sign in',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                            letterSpacing: -0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Войдите в свой аккаунт',
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),

                        if (_savedAccounts.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          _buildSavedAccountsRow(),
                        ],

                        const SizedBox(height: 24),

                        _buildField(
                          controller: _emailController,
                          icon: Icons.person_outline_rounded,
                          hint: 'Email',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        const SizedBox(height: 16),

                        _buildField(
                          controller: _passwordController,
                          focusNode: _passwordFocus,
                          icon: Icons.lock_outline_rounded,
                          hint: 'Пароль',
                          isObscure: _obscurePassword,
                          suffix: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: Colors.grey.shade400,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Transform.scale(
                              scale: 0.9,
                              child: Checkbox(
                                value: _rememberMe,
                                activeColor: _primaryOrange,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                onChanged: (value) =>
                                    setState(() => _rememberMe = value ?? false),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Запомнить меня',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
                              ),
                            ),
                            if (_savedAccounts.isNotEmpty)
                              Tooltip(
                                message:
                                    'Сохранённые аккаунты доступны быстрым входом сверху',
                                child: Icon(
                                  Icons.info_outline_rounded,
                                  size: 16,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 28),

                        ElevatedButton(
                          onPressed: _isLoading ? null : _handleLogin,
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
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text(
                                    key: ValueKey('text'),
                                    'Log in',
                                    style: TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const TenantMainScreen(isGuestMode: true),
                                    ),
                                  );
                                },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _primaryOrange, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            'Войти как гость',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: _primaryOrange,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Нет аккаунта?',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const RegisterScreen(),
                                  ),
                                );
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: _primaryOrange,
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                'Создать аккаунт',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
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

  Widget _buildSavedAccountsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Быстрый вход',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                'Удерживайте, чтобы убрать',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _savedAccounts.length + 1,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index == _savedAccounts.length) {
                return _buildAddAccountChip();
              }
              return _buildAccountChip(_savedAccounts[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAccountChip(SavedAccount account) {
    final isLoading = _resumingEmail == account.email;
    final isCurrent =
        _emailController.text.trim().toLowerCase() == account.email.toLowerCase();

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _handleAccountTap(account),
      onLongPress: () => _confirmRemoveAccount(account),
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent
              ? _primaryOrange.withValues(alpha: 0.08)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent
                ? _primaryOrange.withValues(alpha: 0.45)
                : Colors.grey.shade200,
            width: isCurrent ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                _avatar(account, size: 42, fontSize: 15),
                if (isLoading)
                  const SizedBox(
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFFFF8C00),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _shortLabel(account),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddAccountChip() {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        setState(() {
          _emailController.clear();
          _passwordController.clear();
          _rememberMe = true;
        });
        _passwordFocus.unfocus();
      },
      child: Container(
        width: 88,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.grey.shade300,
            style: BorderStyle.solid,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _primaryOrange.withValues(alpha: 0.08),
                border: Border.all(
                  color: _primaryOrange.withValues(alpha: 0.35),
                  width: 1.2,
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                color: _primaryOrange,
                size: 22,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Другой',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(SavedAccount account, {required double size, required double fontSize}) {
    final isLandlord = account.role == 'LANDLORD';
    final base = isLandlord
        ? const Color(0xFF3F51B5) // Спокойный синий для арендодателя
        : _primaryOrange;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [base, base.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: base.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        account.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: fontSize,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  String _shortLabel(SavedAccount account) {
    if (account.displayName != null && account.displayName!.trim().isNotEmpty) {
      return account.displayName!.trim();
    }
    final at = account.email.indexOf('@');
    return at > 0 ? account.email.substring(0, at) : account.email;
  }

  Widget _buildField({
    required TextEditingController controller,
    required IconData icon,
    required String hint,
    bool isObscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
    FocusNode? focusNode,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      obscureText: isObscure,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.grey.shade500, size: 20),
        suffixIcon: suffix,
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
    _passwordFocus.dispose();
    super.dispose();
  }
}
