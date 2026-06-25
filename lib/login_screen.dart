import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  final String appName;
  final Widget?
  originalHome; // Option to pass the original home screen for reference/debugging

  const LoginScreen({super.key, required this.appName, this.originalHome});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final List<bool> _isSelected = [true, false]; // [利用者, 管理者]
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _autoLogin = false;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = _isSelected[1];

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.appName} - ログイン'),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // アプリ名表示
              Text(
                widget.appName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 32),

              // 「利用者」と「管理者」の切り替えスイッチ
              ToggleButtons(
                isSelected: _isSelected,
                onPressed: (int index) {
                  setState(() {
                    for (int i = 0; i < _isSelected.length; i++) {
                      _isSelected[i] = i == index;
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8.0),
                constraints: const BoxConstraints(minWidth: 120, minHeight: 45),
                selectedColor: Colors.white,
                fillColor: Colors.deepPurple,
                children: const [
                  Text(
                    '利用者',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '管理者',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // ID入力
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'アカウント名/メールアドレス',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _idController,
                decoration: const InputDecoration(
                  hintText: 'アカウント名またはメールアドレスを入力',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // パスワード入力
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'パスワード',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  hintText: 'パスワードを入力',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),

              // 自動ログイン
              Row(
                children: [
                  Checkbox(
                    value: _autoLogin,
                    activeColor: Colors.deepPurple,
                    onChanged: (bool? value) {
                      setState(() {
                        _autoLogin = value ?? false;
                      });
                    },
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _autoLogin = !_autoLogin;
                      });
                    },
                    child: const Text('自動ログインをする'),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // ログインボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    // 各画面へ遷移
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => PlaceholderScreen(
                          appName: widget.appName,
                          isAdmin: isAdmin,
                          originalHome: widget.originalHome,
                        ),
                      ),
                    );
                  },
                  child: const Text(
                    'ログイン',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // パスワードを忘れた場合
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('パスワード再設定メールを送信しました（ダミー）')),
                  );
                },
                child: const Text('パスワードを忘れた方はこちら'),
              ),

              // デバッグ用：元の画面を表示するボタン
              if (widget.originalHome != null) ...[
                const SizedBox(height: 24),
                const Divider(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => widget.originalHome!,
                      ),
                    );
                  },
                  icon: const Icon(Icons.developer_mode),
                  label: const Text('元の画面を表示 (デバッグ用)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// 利用者画面・管理者画面のプレースホルダー
class PlaceholderScreen extends StatelessWidget {
  final String appName;
  final bool isAdmin;
  final Widget? originalHome;

  const PlaceholderScreen({
    super.key,
    required this.appName,
    required this.isAdmin,
    this.originalHome,
  });

  @override
  Widget build(BuildContext context) {
    final String roleName = isAdmin ? '管理者' : '利用者';
    final Color primaryColor = isAdmin ? Colors.red : Colors.blue;

    return Scaffold(
      appBar: AppBar(
        title: Text('$appName - $roleName画面'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              // ログイン画面へ戻る
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      LoginScreen(appName: appName, originalHome: originalHome),
                ),
              );
            },
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isAdmin ? Icons.admin_panel_settings : Icons.person,
                size: 100,
                color: primaryColor,
              ),
              const SizedBox(height: 24),
              Text(
                '$roleName画面',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '※ この画面は $appName の $roleName用画面（後で作成します）のプレースホルダーです。',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => LoginScreen(
                        appName: appName,
                        originalHome: originalHome,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.logout),
                label: const Text('ログイン画面に戻る'),
              ),
              if (originalHome != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => originalHome!),
                    );
                  },
                  icon: const Icon(Icons.developer_mode),
                  label: const Text('元の画面を表示 (デバッグ用)'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
