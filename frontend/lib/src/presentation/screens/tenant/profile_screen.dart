import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../domain/user_profile.dart';
import '../../../services/auth_service.dart';
import '../../../services/image_helper.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(); // <-- Хранилище

  final Color _primaryOrange = const Color(0xFFFF8C00);
  bool _notificationsEnabled = true;
  String _userRole = 'TENANT'; // По умолчанию

  UserProfile? _profile;
  bool _isLoading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final role = await _storage.read(key: 'user_role') ?? 'TENANT';
    if (!mounted) return;
    setState(() {
      _userRole = role;
      _isLoading = true;
      _hasError = false;
    });

    final result = await _authService.getCurrentUserProfile();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      if (result != null) {
        _profile = result;
      } else {
        _hasError = true;
        if (_profile != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нет связи с сервером. Показаны последние данные.'),
              backgroundColor: Colors.black87,
            ),
          );
        }
      }
    });
  }

  void _handleLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выход'),
        content: const Text('Вы уверены, что хотите выйти из аккаунта?'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.black54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Выйти', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (shouldLogout == true) {
      await _authService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
            (route) => false,
      );
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label скопирован в буфер обмена'),
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black87,
      ),
    );
  }

  void _showSupportDialog() {
    const email = 'magomed@magomedov.online';
    const website = 'magomedov.online';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryOrange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.support_agent, color: _primaryOrange),
            ),
            const SizedBox(width: 12),
            const Text('Служба поддержки', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Свяжитесь с разработчиком, если у вас возникли вопросы или предложения:',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _copyToClipboard(email, 'Email'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined, color: Colors.black87, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Email', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          SelectableText(
                            email,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.copy, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _copyToClipboard(website, 'Сайт'),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.public, color: Colors.black87, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Сайт-визитка', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          SelectableText(
                            website,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.copy, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть', style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryOrange.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.info_outline, color: _primaryOrange),
            ),
            const SizedBox(width: 12),
            const Text('О приложении', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _primaryOrange.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.storefront, size: 48, color: _primaryOrange),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Street Retail Aggregator',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Версия 1.0.0',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Платформа, объединяющая арендаторов и арендодателей коммерческой недвижимости в формате street retail.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              const Text(
                'Возможности:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _buildAboutBullet('Поиск помещений на карте'),
              _buildAboutBullet('Подбор по нише и бюджету'),
              _buildAboutBullet('Прямая связь с владельцем'),
              _buildAboutBullet('Избранное и история просмотров'),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                '© 2026 Magomedov\nВсе права защищены',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Закрыть', style: TextStyle(color: _primaryOrange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutBullet(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, size: 16, color: _primaryOrange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Future<void> _changeAvatar(UserProfile profile) async {
    final files = await ImageHelper.pickImages(context, allowMultiple: false);
    if (files.isEmpty) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Загружаем аватар...'), duration: Duration(seconds: 1)),
    );
    final url = await _authService.uploadAvatar(files.first);
    if (!mounted) return;
    if (url != null) {
      _loadProfile();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось загрузить аватар'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteAvatar() async {
    final ok = await _authService.deleteAvatar();
    if (!mounted) return;
    if (ok) {
      _loadProfile();
    }
  }

  void _showAvatarOptions(UserProfile profile) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Изменить аватар'),
              onTap: () {
                Navigator.pop(ctx);
                _changeAvatar(profile);
              },
            ),
            if (profile.avatarUrl != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Удалить аватар', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteAvatar();
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showEditProfileSheet(UserProfile currentProfile) {
    final nameController = TextEditingController(text: currentProfile.name);
    final phoneController = TextEditingController(text: currentProfile.phone);

    int? selectedCategoryId = currentProfile.businessCategoryId;
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateSheet) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 24, right: 24, top: 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Редактировать профиль', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Имя / Компания', prefixIcon: Icon(Icons.person_outline), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Телефон', prefixIcon: Icon(Icons.phone_outlined), border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting ? null : () async {
                        setStateSheet(() => isSubmitting = true);
                        final success = await _authService.updateProfile(nameController.text.trim(), phoneController.text.trim(), selectedCategoryId);
                        setStateSheet(() => isSubmitting = false);

                        if (success) {
                          Navigator.pop(context);
                          _loadProfile();
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: _primaryOrange, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      child: isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Сохранить', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Мой профиль', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: Builder(
        builder: (context) {
          if (_profile == null && _isLoading) {
            return const Center(child: CircularProgressIndicator(color: Colors.black));
          }
          if (_profile == null && _hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off, size: 64, color: Colors.black38),
                    const SizedBox(height: 16),
                    const Text(
                      'Не удалось загрузить профиль.\nПроверьте соединение и попробуйте снова.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 15, color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadProfile,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Повторить'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          final profile = _profile ?? UserProfile(id: 0, name: 'Пользователь', phone: 'Не указан', inn: 'Не указан', businessCategory: 'Не выбрана');

          return RefreshIndicator(
            color: _primaryOrange,
            onRefresh: _loadProfile,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 100),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. ШАПКА
                Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      // АВАТАРКА (сетевая, с тапом для смены)
                      _buildAvatar(profile),
                      const SizedBox(height: 16),
                      Text(profile.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      // БЕЙДЖИК РОЛИ
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                            _userRole == 'LANDLORD' ? 'Арендодатель' : 'Арендатор',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // 2. ДАННЫЕ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        _buildDataRow(Icons.phone_outlined, 'Телефон', profile.phone),
                        const Divider(height: 1, indent: 56),
                        _buildDataRow(Icons.numbers, 'ИНН', profile.inn),
                      ],
                    ),
                  ),
                ),

                // ... ОСТАЛЬНАЯ ЧАСТЬ ЭКРАНА (МЕНЮ И КНОПКА ВЫХОДА) ОСТАЕТСЯ БЕЗ ИЗМЕНЕНИЙ ...
                // Просто скопируй блоки 3. МЕНЮ НАСТРОЕК и 4. ВЫХОД из своего старого файла.

                const SizedBox(height: 24),

                // 3. МЕНЮ НАСТРОЕК
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      children: [
                        _buildMenuTile(
                          icon: Icons.edit_outlined,
                          title: 'Редактировать данные',
                          onTap: () => _showEditProfileSheet(profile),
                        ),
                        const Divider(height: 1, indent: 56),

                        ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                            child: const Icon(Icons.notifications_none, color: Colors.black87),
                          ),
                          title: const Text('Уведомления', style: TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Switch(
                            value: _notificationsEnabled,
                            activeColor: _primaryOrange,
                            onChanged: (value) {
                              setState(() => _notificationsEnabled = value);
                            },
                          ),
                        ),

                        const Divider(height: 1, indent: 56),
                        _buildMenuTile(
                          icon: Icons.help_outline,
                          title: 'Служба поддержки',
                          onTap: _showSupportDialog,
                        ),
                        const Divider(height: 1, indent: 56),
                        _buildMenuTile(
                          icon: Icons.info_outline,
                          title: 'О приложении',
                          onTap: _showAboutDialog,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // 4. ВЫХОД
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('Выйти из аккаунта', style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Colors.red, width: 1.5),
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvatar(UserProfile profile) {
    final remoteUrl = ImageHelper.toAbsoluteUrl(profile.avatarUrl);
    final fallback = AssetImage(
      _userRole == 'LANDLORD' ? 'assets/landlord.png' : 'assets/tenant.png',
    );

    return GestureDetector(
      onTap: () => _showAvatarOptions(profile),
      child: Stack(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[200],
            backgroundImage: remoteUrl != null
                ? CachedNetworkImageProvider(remoteUrl) as ImageProvider
                : fallback,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: _primaryOrange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({required IconData icon, required String title, VoidCallback? onTap}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.black87),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
  }
}