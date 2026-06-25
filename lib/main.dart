// Flutterのモバイルアプリを作るためのツール（パッケージ）を読み込みます
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'login_screen.dart';

// アプリの開始地点（メイン関数）です
void main() {
  runApp(const MyApp());
}

// アプリ全体の見た目や設定を決めるクラスです（StatelessWidget = 状態が変わらない画面）
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '体力表示',
      // アプリ全体のデザイン（テーマ）を設定します
      theme: ThemeData(
        primarySwatch: Colors.blue,
        // ヘッダー（AppBar）のデザイン設定
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0, // ヘッダーの影をなくします
        ),
      ),
      // アプリを起動したときに最初に表示する画面（ホーム画面）
      home: const LoginScreen(
        appName: '体調記録',
        originalHome: HPDisplayPage(pageType: 'HP'),
      ),
    );
  }
}

// 数値が変わる画面を定義します（StatefulWidget）
class HPDisplayPage extends StatefulWidget {
  final String pageType; // HP / MP / LP のどれを表示するかを受け取ります
  const HPDisplayPage({super.key, required this.pageType});

  @override
  State<HPDisplayPage> createState() => _HPDisplayPageState();
}

// 画面の状態（データ）を管理する実体です
class _HPDisplayPageState extends State<HPDisplayPage> {
  // --- システム全体で共有するデータ（static） ---
  // HP、MP、LPの現在の数値（0〜100）
  static double currentHP = 80.0;
  static double currentMP = 80.0;
  static double currentLP = 80.0;
  final double maxValue = 100.0; // 数値の最大値

  // 何が起きて数値が変わったかの履歴リスト
  static List<Map<String, dynamic>> hpEpisodeHistory = [];
  static List<Map<String, dynamic>> mpEpisodeHistory = [];
  static List<Map<String, dynamic>> lpEpisodeHistory = [];

  // ログインした時刻（シミュレーション用：27分前に設定）
  static DateTime loginTime = DateTime.now().subtract(
    const Duration(minutes: 27),
  );

  // --- 1時間ごとHP通知用タイマー ---
  Timer? _hourlyTimer;        // 定期チェック用タイマー
  int? _lastNotifiedHour;     // 最後に通知した「時」（二重表示防止）

  @override
  void initState() {
    super.initState();
    // データベースから保存されたデータを取り込みます
    _loadFromDatabase();
    // 1時間ごとHP通知タイマーを開始
    _startHourlyNotification();
  }

  Future<void> _loadFromDatabase() async {
    final db = DatabaseHelper.instance;
    final hp = await db.getStatus('hp');
    final mp = await db.getStatus('mp');
    final lp = await db.getStatus('lp');
    final hpHistory = await db.getHistory('HP');
    final mpHistory = await db.getHistory('MP');
    final lpHistory = await db.getHistory('LP');

    setState(() {
      currentHP = hp;
      currentMP = mp;
      currentLP = lp;
      hpEpisodeHistory = hpHistory;
      mpEpisodeHistory = mpHistory;
      lpEpisodeHistory = lpHistory;
    });
  }

  // -------------------------------------------------------
  // 1時間ごとHP通知ロジック
  // -------------------------------------------------------

  /// 30秒ごとに端末時刻をチェックし、9〜15時の丁度（minute == 0）に
  /// かつその「時」にまだ通知していない場合のみダイアログを表示する
  void _startHourlyNotification() {
    _hourlyTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final hour = now.hour;
      final minute = now.minute;

      // 対象時間帯: 9時〜15時（9,10,11,12,13,14,15）
      final isTargetHour = hour >= 9 && hour <= 15;
      // 丁度（0分）かどうか
      final isOnTheHour = minute == 0;
      // 同じ時間帯にすでに通知済みでないか
      final alreadyNotified = _lastNotifiedHour == hour;

      if (isTargetHour && isOnTheHour && !alreadyNotified) {
        _lastNotifiedHour = hour;
        _showConditionDialog();
      }
    });
  }

  /// 調子確認ダイアログを表示する
  void _showConditionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false, // 必ずボタンを選んで閉じる
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.favorite, color: Color(0xFF00FFFF)),
              SizedBox(width: 8),
              Text(
                '今の調子はどうですか？',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _conditionButton(ctx, '😢 悪い',       const Color(0xFFEF5350), -5.0),
              const SizedBox(height: 8),
              _conditionButton(ctx, '😟 少し悪い',   const Color(0xFFFF8A65), -3.0),
              const SizedBox(height: 8),
              _conditionButton(ctx, '😐 普通',        const Color(0xFF90A4AE),  0.0),
              const SizedBox(height: 8),
              _conditionButton(ctx, '😊 少し良い',   const Color(0xFF66BB6A), 3.0),
              const SizedBox(height: 8),
              _conditionButton(ctx, '😄 良い',        const Color(0xFF42A5F5), 5.0),
            ],
          ),
        );
      },
    );
  }

  /// ダイアログ内の各選択ボタンを生成する
  Widget _conditionButton(BuildContext ctx, String label, Color color, double delta) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: () {
          Navigator.of(ctx).pop(); // ダイアログを閉じる
          _applyConditionChange(delta);
        },
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  /// HP値を delta だけ増減してデータベースへ保存する
  Future<void> _applyConditionChange(double delta) async {
    if (delta == 0.0) return; // 「普通」の場合は変化なし

    final double newValue = (currentHP + delta).clamp(0.0, maxValue);

    final db = DatabaseHelper.instance;
    await db.saveStatus('HP', newValue);

    final label = delta > 0 ? '+${delta.toInt()}' : '${delta.toInt()}';
    final newHistoryItem = {
      'datetime': DateTime.now(),
      'episode': '調子チェック（$label%）',
      'change': delta,
    };
    await db.insertHistory('HP', newHistoryItem);

    final updatedHistory = await db.getHistory('HP');

    if (!mounted) return;
    setState(() {
      currentHP = newValue;
      hpEpisodeHistory = updatedHistory;
    });
  }

  // --- この画面だけで使うパーツ（コントローラーなど） ---
  // 入力欄の内容を操作するためのツール
  final TextEditingController episodeController = TextEditingController();
  // 選択された増減値（プルダウン用）
  int selectedPercentage = 0;

  // 遡り記録用の日時（初期値は現在時刻）
  DateTime selectedDateTime = DateTime.now();

  // 日時を選択するダイアログを表示する関数
  Future<void> _pickDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDateTime,
      firstDate: DateTime.now().subtract(const Duration(hours: 48)),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      if (!mounted) return;
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(selectedDateTime),
      );

      if (pickedTime != null) {
        setState(() {
          selectedDateTime = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }

  // プルダウンメニューに表示する選択肢（+100%から-100%まで）
  final List<int> percentageOptions = [
    100,
    95,
    90,
    85,
    80,
    75,
    70,
    65,
    60,
    55,
    50,
    45,
    40,
    35,
    30,
    25,
    20,
    15,
    10,
    5,
    0,
    -5,
    -10,
    -15,
    -20,
    -25,
    -30,
    -35,
    -40,
    -45,
    -50,
    -55,
    -60,
    -65,
    -70,
    -75,
    -80,
    -85,
    -90,
    -95,
    -100,
  ];

  // ダミーの他ユーザーデータ（本来はデータベースから取得します）
  final List<Map<String, dynamic>> otherUsers = [
    {
      'name': '田中 太郎',
      'hp': 80.0,
      'mp': 60.0,
      'lp': 90.0,
      'color': Colors.blue,
      'hasUnread': true, // 未読あり
      'lastUpdated': DateTime.now().subtract(const Duration(minutes: 5)),
      'lastMessageTime': DateTime.now().subtract(const Duration(minutes: 10)),
    },
    {
      'name': '佐藤 花子',
      'hp': 85.0,
      'mp': 70.0,
      'lp': 80.0,
      'color': Colors.green,
      'hasUnread': true,
      'lastUpdated': DateTime.now().subtract(const Duration(minutes: 2)),
      'lastMessageTime': DateTime.now().subtract(const Duration(minutes: 2)),
    },
    {
      'name': '鈴木 一郎',
      'hp': 75.0,
      'mp': 90.0,
      'lp': 65.0,
      'color': Colors.orange,
      'hasUnread': false,
      'lastUpdated': DateTime.now().subtract(const Duration(minutes: 30)),
      'lastMessageTime': DateTime.now().subtract(const Duration(hours: 5)),
    },
    {
      'name': '高橋 美咲',
      'hp': 90.0,
      'mp': 85.0,
      'lp': 75.0,
      'color': Colors.purple,
      'hasUnread': false,
      'lastUpdated': DateTime.now().subtract(const Duration(hours: 1)),
      'lastMessageTime': DateTime.now().subtract(const Duration(hours: 2)),
    },
    {
      'name': '佐々木 健一',
      'hp': 70.0,
      'mp': 65.0,
      'lp': 95.0,
      'color': Colors.red,
      'hasUnread': false,
      'lastUpdated': DateTime.now().subtract(const Duration(minutes: 15)),
      'lastMessageTime': DateTime.now().subtract(const Duration(minutes: 20)),
    },
    {
      'name': '山田 圭太',
      'hp': 95.0,
      'mp': 80.0,
      'lp': 70.0,
      'color': Colors.teal,
      'hasUnread': false,
      'lastUpdated': DateTime.now().subtract(const Duration(minutes: 45)),
      'lastMessageTime': DateTime.now().subtract(const Duration(hours: 1)),
    },
    {
      'name': '桜姫 凉華',
      'hp': 60.0,
      'mp': 75.0,
      'lp': 85.0,
      'color': Colors.pink,
      'hasUnread': false,
      'lastUpdated': DateTime.now().subtract(const Duration(hours: 2)),
      'lastMessageTime': DateTime.now().subtract(const Duration(hours: 3)),
    },
    {
      'name': '桑村 慎二',
      'hp': 88.0,
      'mp': 95.0,
      'lp': 60.0,
      'color': Colors.indigo,
      'hasUnread': false,
      'lastUpdated': DateTime.now().subtract(const Duration(minutes: 10)),
      'lastMessageTime': DateTime.now().subtract(const Duration(minutes: 15)),
    },
  ];

  // 並び替えの種類
  String _sortType = 'login'; // login, status, message

  // --- 便利な道具（関数）たち ---

  // ユーザーを選ばれた方法で並び替える関数
  List<Map<String, dynamic>> getSortedUsers() {
    List<Map<String, dynamic>> sortedList = List.from(otherUsers);
    sortedList.sort((a, b) {
      if (_sortType == 'login') {
        // ログイン時間が近い順（降順）
        DateTime timeA = a['lastUpdated'] as DateTime;
        DateTime timeB = b['lastUpdated'] as DateTime;
        return timeB.compareTo(timeA);
      } else if (_sortType == 'status') {
        // ステータスが小さい順（昇順）
        String key = widget.pageType.toLowerCase();
        double valA = (a[key] as num).toDouble();
        double valB = (b[key] as num).toDouble();
        return valA.compareTo(valB);
      } else if (_sortType == 'message_newest') {
        // 未読メッセージ優先、かつ新しい順
        bool unreadA = a['hasUnread'] ?? false;
        bool unreadB = b['hasUnread'] ?? false;
        if (unreadA != unreadB) {
          return unreadA ? -1 : 1; // 未読を上に
        }
        DateTime timeA = a['lastMessageTime'] as DateTime;
        DateTime timeB = b['lastMessageTime'] as DateTime;
        return timeB.compareTo(timeA);
      } else if (_sortType == 'message_oldest') {
        // 未読メッセージ優先、かつ古い順
        bool unreadA = a['hasUnread'] ?? false;
        bool unreadB = b['hasUnread'] ?? false;
        if (unreadA != unreadB) {
          return unreadA ? -1 : 1; // 未読を上に
        }
        DateTime timeA = a['lastMessageTime'] as DateTime;
        DateTime timeB = b['lastMessageTime'] as DateTime;
        return timeA.compareTo(timeB);
      }
      return 0;
    });
    return sortedList;
  }

  // 今表示しているページ（HP/MP/LP）に合わせて、現在の数値を取り出す関数
  double getCurrentValue() {
    switch (widget.pageType) {
      case 'MP':
        return currentMP;
      case 'LP':
        return currentLP;
      default:
        return currentHP;
    }
  }

  // 今表示しているページに合わせて、数値をセット（保存）する関数
  void setCurrentValue(double value) {
    setState(() {
      // setStateを呼ぶことで画面を再描画（リフレッシュ）します
      switch (widget.pageType) {
        case 'MP':
          currentMP = value;
          break;
        case 'LP':
          currentLP = value;
          break;
        default:
          currentHP = value;
      }
    });
  }

  // 今表示しているページに合わせて、履歴リストを取り出す関数
  List<Map<String, dynamic>> getHistory() {
    switch (widget.pageType) {
      case 'MP':
        return mpEpisodeHistory;
      case 'LP':
        return lpEpisodeHistory;
      default:
        return hpEpisodeHistory;
    }
  }

  // ページの種類（HP/MP/LP）に合わせてバーの色を決める関数
  Color getBarColor() {
    switch (widget.pageType) {
      case 'MP':
        return const Color(0xFF00FF00); // 緑
      case 'LP':
        return const Color(0xFFFFFF00); // 黄
      default:
        return const Color(0xFF00FFFF); // 水色
    }
  }

  // 画面上部に表示するタイトルを決める関数
  String getTitle() {
    switch (widget.pageType) {
      case 'MP':
        return '精神力表示';
      case 'LP':
        return '運勢表示';
      default:
        return '体力表示';
    }
  }

  // 「何分前」といった経過時間を計算して文字で返す関数
  String getLoginTimeAgo() {
    final now = DateTime.now();
    final difference = now.difference(loginTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}時間前';
    } else {
      return '${difference.inDays}日前';
    }
  }

  // --- 画面の部品を作る関数 ---

  // 数値を表すバー（HPバーなど）を作るための関数
  Widget buildGradientHPBar({double? value, bool showPercentage = true}) {
    double barValue = value ?? getCurrentValue();
    double percentage = (barValue / maxValue * 100);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(13), // 枠の丸み
      ),
      child: Stack(
        // 重なりを作るウィジェット（背景と色付きバーを重ねる）
        children: [
          // 背景のグレーのバー
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          // 現在値を示す色付きのバー
          FractionallySizedBox(
            // 親（Container）の幅に対して割合でサイズを決めます
            widthFactor: barValue / maxValue,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: getBarColor(),
                borderRadius: BorderRadius.circular(10),
              ),
              child: showPercentage
                  ? Center(
                      child: Text(
                        '${percentage.toInt()}%',
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // 「確定」ボタンが押された時の処理
  Future<void> applyPercentage() async {
    String episode = episodeController.text.trim(); // 入力されたエピソード（前後の空白を削除）

    // 0%が選ばれている時は何もしない
    if (selectedPercentage == 0) return;

    double value = selectedPercentage.toDouble();
    // 現在の値に足し算し、0〜100の範囲に収めます
    double newValue = (getCurrentValue() + value).clamp(0.0, maxValue);
    setCurrentValue(newValue);

    // データベースに保存します
    final db = DatabaseHelper.instance;
    db.saveStatus(widget.pageType, newValue);

    final newHistoryItem = {
      'datetime': selectedDateTime,
      'episode': episode.isEmpty ? '(エピソードなし)' : episode,
      'change': value,
    };
    await db.insertHistory(widget.pageType, newHistoryItem);

    // 最新の履歴（ID付き）を取得するために再読み込み
    final updatedHistory = await db.getHistory(widget.pageType);

    setState(() {
      if (widget.pageType == 'HP')
        _HPDisplayPageState.hpEpisodeHistory = updatedHistory;
      if (widget.pageType == 'MP')
        _HPDisplayPageState.mpEpisodeHistory = updatedHistory;
      if (widget.pageType == 'LP')
        _HPDisplayPageState.lpEpisodeHistory = updatedHistory;

      selectedPercentage = 0; // 選択肢をリセット
      selectedDateTime = DateTime.now(); // 日時も現在時刻にリセット
    });
    episodeController.clear(); // 入力欄を空にします
  }

  // 履歴を削除し、数値を再計算する関数
  Future<void> deleteHistoryItem(int id, String type) async {
    final db = DatabaseHelper.instance;
    await db.deleteHistory(id);

    // 履歴を再取得
    final updatedHistory = await db.getHistory(type);

    // 数値を再計算 (初期値 80.0 + 履歴の増減の合計)
    double totalChange = 0;
    for (var item in updatedHistory) {
      totalChange += (item['change'] as num).toDouble();
    }
    double newValue = (80.0 + totalChange).clamp(0.0, 100.0);

    // データベースのステータスを更新
    await db.saveStatus(type, newValue);

    setState(() {
      if (type == 'HP') {
        _HPDisplayPageState.currentHP = newValue;
        _HPDisplayPageState.hpEpisodeHistory = updatedHistory;
      } else if (type == 'MP') {
        _HPDisplayPageState.currentMP = newValue;
        _HPDisplayPageState.mpEpisodeHistory = updatedHistory;
      } else if (type == 'LP') {
        _HPDisplayPageState.currentLP = newValue;
        _HPDisplayPageState.lpEpisodeHistory = updatedHistory;
      }
    });
  }

  // ヒストリー画面へ移動（ナビゲーション）する関数
  void navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryPage(
          pageType: widget.pageType,
          currentValue: getCurrentValue(),
          maxValue: maxValue,
          history: getHistory(),
          barColor: getBarColor(),
          loginTime: loginTime,
          onDelete: (id, type) => deleteHistoryItem(id, type),
        ),
      ),
    );
  }

  // 他のユーザーの行（アイコン、名前、バー）を作るための関数
  Widget buildOtherUserHP(Map<String, dynamic> user) {
    bool hasUnread = user['hasUnread'] ?? false; // 未読メッセージがあるか

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          // ユーザー情報をタップできるようにします
          Expanded(
            child: InkWell(
              onTap: () {
                // タップしたらそのユーザーのヒストリー画面へ移動
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserHistoryPage(
                      userData: user,
                      initialPageType: widget.pageType,
                    ),
                  ),
                );
              },
              child: Row(
                children: [
                  // ユーザーアイコンと名前
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 25,
                        backgroundColor: user['color'],
                        child: Text(
                          user['name'][0], // 名前の最初の1文字
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 60,
                        child: Text(
                          user['name'],
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2, // 2行まで表示
                          overflow: TextOverflow.ellipsis, // 超えたら「...」
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // 他のユーザーのバー
                  Expanded(
                    child: buildGradientHPBar(
                      value: (user[widget.pageType.toLowerCase()] as num)
                          .toDouble(),
                      showPercentage: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // チャットボタン
          Column(
            children: [
              IconButton(
                icon: Icon(
                  Icons.message,
                  color: hasUnread ? Colors.red : Colors.blue,
                ),
                onPressed: () {
                  // メッセージダイアログ（ポップアップ）を表示します
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return ChatDialog(userName: user['name']);
                    },
                  );
                },
                tooltip: 'メッセージを送る',
              ),
              if (hasUnread)
                const Text(
                  '未読',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 表示する履歴データ（HP/MP/LPのどれか）を準備します
    var episodeHistory = getHistory();

    return Scaffold(
      backgroundColor: Colors.transparent, // 背景を透明にして下のグラデーションを見せます
      appBar: AppBar(
        title: Text(getTitle()), // ページ名に合わせたタイトルを表示
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        // 画面全体の背景にグラデーションを設定します
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF), // 上：白
              Color(0xFFDFFFBF), // 下：薄い緑
            ],
          ),
        ),
        child: SingleChildScrollView(
          // 画面が入りきらない場合にスクロールできるようにします
          child: Padding(
            padding: const EdgeInsets.all(10.0), // 画面端の余白
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HP / MP / LP 切り替えボタンエリア ---
                const SizedBox(height: 5),
                Row(
                  children: [
                    _buildTabButton('HP'),
                    const SizedBox(width: 6),
                    _buildTabButton('MP'),
                    const SizedBox(width: 6),
                    _buildTabButton('LP'),
                    const Spacer(), // 右端に寄せるためのスペース
                    // ヒストリー画面へのボタン
                    ElevatedButton(
                      onPressed: navigateToHistory,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.black),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('ヒストリー'),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // --- 自分のプロフィールエリア ---
                Center(
                  child: Column(
                    children: [
                      // 丸いアイコン
                      CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.blue,
                        child: const Icon(
                          Icons.person,
                          size: 50,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // ユーザー名
                      const Text(
                        'KEN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                // --- 自分のステータスバー ---
                buildGradientHPBar(),
                const SizedBox(height: 20),

                // --- エピソードと数値の入力エリア ---
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      // テキスト入力欄
                      TextField(
                        controller: episodeController,
                        decoration: const InputDecoration(
                          hintText: '今の出来事を入力してね',
                          border: InputBorder.none,
                        ),
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 日時選択ボタン
                          TextButton.icon(
                            onPressed: _pickDateTime,
                            icon: const Icon(Icons.access_time, size: 18),
                            label: Text(
                              '${selectedDateTime.month}/${selectedDateTime.day} ${selectedDateTime.hour}:${selectedDateTime.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blueGrey,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                          Row(
                            children: [
                              // パーセンテージ（増減）の選択
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButton<int>(
                                  value: selectedPercentage,
                                  underline: const SizedBox(),
                                  items: percentageOptions.map((int value) {
                                    Color itemColor = Colors.black;
                                    if (value > 0) itemColor = Colors.blue;
                                    if (value < 0) itemColor = Colors.red;

                                    return DropdownMenuItem<int>(
                                      value: value,
                                      child: Text(
                                        value == 0
                                            ? '0'
                                            : '${value > 0 ? '+' : ''}$value%',
                                        style: TextStyle(
                                          color: itemColor,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (int? newValue) {
                                    setState(() {
                                      selectedPercentage = newValue!;
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              // 確定ボタン
                              ElevatedButton(
                                onPressed: applyPercentage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('確定'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),

                // --- 履歴表示（簡易版） ---
                if (episodeHistory.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '履歴',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // 最新の3件だけ表示します
                        ...episodeHistory.take(3).map((history) {
                          DateTime dt = history['datetime'];
                          String timeStr =
                              '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    history['episode'],
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${history['change'] > 0 ? '+' : ''}${history['change']}%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: history['change'] > 0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    size: 18,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () => deleteHistoryItem(
                                    history['id'] as int,
                                    widget.pageType,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],

                // 区切り線
                const Divider(thickness: 2),
                const SizedBox(height: 10),

                // --- 他のユーザーたちの表示エリア ---
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'ユーザーリスト',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // 並び替え用プルダウン
                    DropdownButton<String>(
                      value: _sortType,
                      icon: const Icon(Icons.sort, size: 16),
                      style: const TextStyle(color: Colors.black, fontSize: 13),
                      underline: Container(height: 1, color: Colors.blueGrey),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _sortType = newValue;
                          });
                        }
                      },
                      items: [
                        const DropdownMenuItem(
                          value: 'login',
                          child: Text('ログイン順'),
                        ),
                        DropdownMenuItem(
                          value: 'status',
                          child: Text('${widget.pageType}が小さい順'),
                        ),
                        const DropdownMenuItem(
                          value: 'message_newest',
                          child: Text('未読メッセージが新しい順'),
                        ),
                        const DropdownMenuItem(
                          value: 'message_oldest',
                          child: Text('未読メッセージが古い順'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 更新順に並び替えて、一人ずつリストとして表示します
                ...getSortedUsers().map((user) => buildOtherUserHP(user)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- タブボタン単体を作る関数 ---
  Widget _buildTabButton(String label) {
    bool isSelected = widget.pageType == label; // 今選ばれているかどうか
    return ElevatedButton(
      onPressed: () {
        // 別のタブが押されたら、そのページに切り替えます
        if (label != widget.pageType) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => HPDisplayPage(pageType: label),
            ),
          );
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.black : Colors.white, // 選ばれていれば黒
        foregroundColor: isSelected ? Colors.white : Colors.black, // 選ばれていれば白文字
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Text(label),
    );
  }

  @override
  void dispose() {
    // タイマーのキャンセル
    _hourlyTimer?.cancel();
    // コントローラーのメモリ解放
    episodeController.dispose();
    super.dispose();
  }
}

// --- チャット画面（ポップアップ）のクラス ---
class ChatDialog extends StatefulWidget {
  final String userName; // 誰とチャットするかを受け取ります

  const ChatDialog({super.key, required this.userName});

  @override
  State<ChatDialog> createState() => _ChatDialogState();
}

class _ChatDialogState extends State<ChatDialog> {
  // メッセージ入力用のツール
  final TextEditingController messageController = TextEditingController();
  // チャットメッセージを保存するリスト
  final List<Map<String, String>> messages = [];

  // メッセージを「送信」する時の処理
  void sendMessage() {
    String message = messageController.text.trim();
    if (message.isEmpty) return; // 空っぽなら送らない

    setState(() {
      // 自分のメッセージをリストに追加
      messages.add({
        'sender': 'KEN',
        'message': message,
        'time':
            '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      });
    });
    messageController.clear(); // 入力欄をリセット
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      // ポップアップウィンドウを表示するウィジェット
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        height: 500,
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // チャットのヘッダー（名前と閉じるボタン）
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(), // ダイアログを閉じます
                ),
              ],
            ),
            const Divider(),
            // メッセージが表示されるエリア
            Expanded(
              child: messages.isEmpty
                  ? const Center(
                      child: Text(
                        'メッセージを送ってみよう！',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      // リストをスクロール表示するためのウィジェット
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // アイコン
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.blue,
                                child: Text(
                                  msg['sender']![0],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              // メッセージの内容と送信時刻
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          msg['sender']!,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          msg['time']!,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    // 吹き出し部分
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(msg['message']!),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            // 文字を入力する場所
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 10,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 送信ボタン（飛行機のアイコン）
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }
}

// --- 自分の詳細な履歴（ヒストリー）を表示する画面 ---
class HistoryPage extends StatefulWidget {
  final String pageType;
  final double currentValue;
  final double maxValue;
  final List<Map<String, dynamic>> history; // 表示する履歴データ
  final Color barColor;
  final DateTime loginTime;
  final Future<void> Function(int id, String type) onDelete;

  const HistoryPage({
    super.key,
    required this.pageType,
    required this.currentValue,
    required this.maxValue,
    required this.history,
    required this.barColor,
    required this.loginTime,
    required this.onDelete,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  // 表示用のローカルな状態
  late double _currentValue;
  late List<Map<String, dynamic>> _history;
  late String _pageType;
  late Color _barColor;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.currentValue;
    _history = widget.history;
    _pageType = widget.pageType;
    _barColor = widget.barColor;
  }

  // 他のタブ（HP/MP/LP）の履歴に切り替える関数
  void navigateToPage(String newPageType) {
    setState(() {
      _pageType = newPageType;
      switch (newPageType) {
        case 'MP':
          _currentValue = _HPDisplayPageState.currentMP;
          _history = _HPDisplayPageState.mpEpisodeHistory;
          _barColor = const Color(0xFF00FF00);
          break;
        case 'LP':
          _currentValue = _HPDisplayPageState.currentLP;
          _history = _HPDisplayPageState.lpEpisodeHistory;
          _barColor = const Color(0xFFFFFF00);
          break;
        default:
          _currentValue = _HPDisplayPageState.currentHP;
          _history = _HPDisplayPageState.hpEpisodeHistory;
          _barColor = const Color(0xFF00FFFF);
      }
    });
  }

  // ログイン経過時間を文字列にする関数
  String getLoginTimeAgo() {
    final now = DateTime.now();
    final difference = now.difference(widget.loginTime);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}時間前';
    } else {
      return '${difference.inDays}日前';
    }
  }

  // 履歴画面用のステータスバーを構築する関数
  Widget buildBar() {
    double percentage = (_currentValue / widget.maxValue * 100);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Stack(
        children: [
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          FractionallySizedBox(
            widthFactor: _currentValue / widget.maxValue,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: _barColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${percentage.toInt()}%',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('ヒストリー')),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFDFFFBF)],
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タブ切り替えボタン
                const SizedBox(height: 5),
                Row(
                  children: [
                    _buildTabButton('HP'),
                    const SizedBox(width: 6),
                    _buildTabButton('MP'),
                    const SizedBox(width: 6),
                    _buildTabButton('LP'),
                    const Spacer(),
                    // 「グラフ」ボタン
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GraphPage(
                              userName: 'KEN',
                              hpHistory: _HPDisplayPageState.hpEpisodeHistory,
                              mpHistory: _HPDisplayPageState.mpEpisodeHistory,
                              lpHistory: _HPDisplayPageState.lpEpisodeHistory,
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.black),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('グラフ'),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // プロフィール部分（アイコンと現在のバーを表示）
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.blue,
                      child: const Icon(
                        Icons.person,
                        size: 30,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: buildBar()),
                  ],
                ),
                const SizedBox(height: 15),

                // 名前とログイン時間
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'KEN',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('ログイン', style: TextStyle(fontSize: 14)),
                    Text(
                      getLoginTimeAgo(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 履歴の一覧リスト
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ヒストリー',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      // 履歴が空の場合の表示
                      if (_history.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text('まだヒストリーがありません'),
                          ),
                        )
                      else
                        // 履歴があれば、一つずつ表示します
                        ..._history.map((item) {
                          DateTime dt = item['datetime'];
                          String timeStr =
                              '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                          bool isPositive = item['change'] > 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Expanded(
                                  child: Text(
                                    item['episode'],
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // 増減値と発生時刻
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isPositive ? '+' : ''}${item['change'].toInt()}%',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isPositive
                                            ? Colors.blue
                                            : Colors.red,
                                      ),
                                    ),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isPositive
                                            ? Colors.blue.withValues(alpha: 0.6)
                                            : Colors.red.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.grey,
                                  ),
                                  onPressed: () async {
                                    // 削除処理を待つ
                                    await widget.onDelete(
                                      item['id'] as int,
                                      _pageType,
                                    );
                                    // 削除が終わったら、共有されている最新データで自分の画面を更新する
                                    setState(() {
                                      switch (_pageType) {
                                        case 'MP':
                                          _currentValue =
                                              _HPDisplayPageState.currentMP;
                                          _history = _HPDisplayPageState
                                              .mpEpisodeHistory;
                                          break;
                                        case 'LP':
                                          _currentValue =
                                              _HPDisplayPageState.currentLP;
                                          _history = _HPDisplayPageState
                                              .lpEpisodeHistory;
                                          break;
                                        default:
                                          _currentValue =
                                              _HPDisplayPageState.currentHP;
                                          _history = _HPDisplayPageState
                                              .hpEpisodeHistory;
                                      }
                                    });
                                  },
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // タブボタンを作る関数
  Widget _buildTabButton(String label) {
    bool isSelected = _pageType == label;
    return ElevatedButton(
      onPressed: () {
        if (label != _pageType) {
          navigateToPage(label);
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.black : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Text(label),
    );
  }
}

// --- 他のユーザーの詳細な履歴（ヒストリー）を表示する画面 ---
class UserHistoryPage extends StatefulWidget {
  final Map<String, dynamic> userData; // 表示するユーザーのデータ
  final String initialPageType; // 初期表示するタブ（HP/MP/LP）

  const UserHistoryPage({
    super.key,
    required this.userData,
    this.initialPageType = 'HP',
  });

  @override
  State<UserHistoryPage> createState() => _UserHistoryPageState();
}

class _UserHistoryPageState extends State<UserHistoryPage> {
  late String currentPageType;
  late double currentValue;
  late Color currentColor;
  late List<Map<String, dynamic>> currentHistory;
  final double maxValue = 100.0;

  @override
  void initState() {
    super.initState();
    // 画面が開いたときに、指定されたタブ（HPなど）のデータを読み込みます
    currentPageType = widget.initialPageType;
    _loadDataForType(currentPageType);
  }

  // ページの種類（HP/MP/LP）に合わせて表示データを切り替える関数
  void _loadDataForType(String type) {
    setState(() {
      currentPageType = type;
      // HPは元のデータを使用し、MP/LPはデモ用の固定値を使います
      if (type == 'HP') {
        currentValue = widget.userData['hp'];
        currentColor = const Color(0xFF00FFFF);
      } else if (type == 'MP') {
        currentValue = 65.0;
        currentColor = const Color(0xFF00FF00);
      } else {
        currentValue = 40.0;
        currentColor = const Color(0xFFFFFF00);
      }

      // デモ用の履歴データを生成します
      currentHistory = _generateDummyHistory(type);
    });
  }

  // デモ用の適当な履歴データを作る関数
  List<Map<String, dynamic>> _generateDummyHistory(String type) {
    return [
      {
        'id': 1, // ダミーIDを追加
        'datetime': DateTime.now().subtract(const Duration(minutes: 30)),
        'episode': '$type回復アイテムを使用しました',
        'change': 10.0,
      },
      {
        'id': 2, // ダミーIDを追加
        'datetime': DateTime.now().subtract(const Duration(hours: 2)),
        'episode': '難易度の高いタスクを完了',
        'change': -15.0,
      },
      {
        'id': 3, // ダミーIDを追加
        'datetime': DateTime.now().subtract(const Duration(days: 1)),
        'episode': '昨日はよく眠れました',
        'change': 20.0,
      },
    ];
  }

  // ステータスバーを構築する関数
  Widget buildBar() {
    double percentage = (currentValue / maxValue * 100);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Stack(
        children: [
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          FractionallySizedBox(
            widthFactor: currentValue / maxValue,
            child: Container(
              height: 30,
              decoration: BoxDecoration(
                color: currentColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '${percentage.toInt()}%',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // タブ切り替えボタンを作る関数
  Widget _buildTabButton(String label) {
    bool isSelected = currentPageType == label;
    return ElevatedButton(
      onPressed: () {
        if (label != currentPageType) {
          _loadDataForType(label); // データをロードし直して画面を更新
        }
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.black : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.black,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.black),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Text(label),
    );
  }

  // 最終更新からの経過時間を計算する関数
  String getLastUpdatedTime() {
    final lastUpdated = widget.userData['lastUpdated'] as DateTime;
    final now = DateTime.now();
    final difference = now.difference(lastUpdated);

    if (difference.inMinutes < 60) {
      return '${difference.inMinutes}分前';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}時間前';
    } else {
      return '${difference.inDays}日前';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('${widget.userData['name']}のヒストリー'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context), // 前の画面に戻ります
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFDFFFBF)],
          ),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // タブ切り替えボタン
                const SizedBox(height: 5),
                Row(
                  children: [
                    _buildTabButton('HP'),
                    const SizedBox(width: 6),
                    _buildTabButton('MP'),
                    const SizedBox(width: 6),
                    _buildTabButton('LP'),
                    const Spacer(),
                    // 「グラフ」ボタン
                    ElevatedButton(
                      onPressed: () {
                        // 他ユーザーの場合はダミーデータでグラフを表示します
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GraphPage(
                              userName: widget.userData['name'],
                              // 他ユーザーの過去データはシミュレーションとして生成
                              hpHistory: _generateDummyHistory('HP'),
                              mpHistory: _generateDummyHistory('MP'),
                              lpHistory: _generateDummyHistory('LP'),
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Colors.black),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                      ),
                      child: const Text('グラフ'),
                    ),
                  ],
                ),
                const SizedBox(height: 15),

                // ユーザーアイコンと現在のバー
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: widget.userData['color'],
                      child: Text(
                        widget.userData['name'][0],
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: buildBar()), // 数値バーを表示
                  ],
                ),
                const SizedBox(height: 15),

                // ユーザー名と最終更新時間
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.userData['name'],
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text('最終更新', style: TextStyle(fontSize: 14)),
                    Text(
                      getLastUpdatedTime(),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ヒストリーリスト（他ユーザー用）
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ヒストリー',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 15),
                      if (currentHistory.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: Text('まだヒストリーがありません'),
                          ),
                        )
                      else
                        // 履歴の各項目を表示します
                        ...currentHistory.map((item) {
                          DateTime dt = item['datetime'];
                          String timeStr =
                              '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                          bool isPositive = item['change'] > 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '• ',
                                  style: TextStyle(fontSize: 16),
                                ),
                                Expanded(
                                  child: Text(
                                    item['episode'],
                                    style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${isPositive ? '+' : ''}${item['change'].toInt()}%',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: isPositive
                                            ? Colors.blue
                                            : Colors.red,
                                      ),
                                    ),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isPositive
                                            ? Colors.blue.withValues(alpha: 0.6)
                                            : Colors.red.withValues(alpha: 0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- グラフを表示する画面のクラス ---
class GraphPage extends StatefulWidget {
  final String userName;
  final List<Map<String, dynamic>> hpHistory;
  final List<Map<String, dynamic>> mpHistory;
  final List<Map<String, dynamic>> lpHistory;

  const GraphPage({
    super.key,
    required this.userName,
    required this.hpHistory,
    required this.mpHistory,
    required this.lpHistory,
  });

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  int selectedHours = 48; // デフォルトは48時間

  // 履歴データからグラフ用のポイントデータと注釈（エピソード）を作成する補助関数
  ({List<FlSpot> spots, List<String> episodes}) _generateSpots(
    List<Map<String, dynamic>> history,
    double initialValue,
  ) {
    List<({FlSpot spot, String episode})> points = [];
    DateTime now = DateTime.now();

    // 選択された時間範囲で設定
    double maxX = selectedHours.toDouble();

    // 1. 現在値を最新の点として追加
    points.add((spot: FlSpot(maxX, initialValue), episode: '現在'));

    // 2. 履歴から点を逆算
    double runningValue = initialValue;
    for (var item in history) {
      DateTime dt = item['datetime'];
      double diffHours = now.difference(dt).inMinutes / 60.0;
      double x = maxX - diffHours;
      if (x < 0) break; // 選択範囲外は無視

      // change分を引いて「その時の値」を出す
      runningValue -= item['change'];
      points.add((
        spot: FlSpot(x, runningValue.clamp(0, 100)),
        episode: item['episode'] ?? '',
      ));
    }

    // X軸でソート
    points.sort((a, b) => a.spot.x.compareTo(b.spot.x));

    return (
      spots: points.map((p) => p.spot).toList(),
      episodes: points.map((p) => p.episode).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // データの準備
    final hpData = _generateSpots(
      widget.hpHistory,
      _HPDisplayPageState.currentHP,
    );
    final mpData = _generateSpots(
      widget.mpHistory,
      _HPDisplayPageState.currentMP,
    );
    final lpData = _generateSpots(
      widget.lpHistory,
      _HPDisplayPageState.currentLP,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.userName}のステータス推移'),
        actions: [
          // 表示範囲選択のプルダウン
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: DropdownButton<int>(
              value: selectedHours,
              dropdownColor: Colors.white,
              onChanged: (int? newValue) {
                if (newValue != null) {
                  setState(() {
                    selectedHours = newValue;
                  });
                }
              },
              items: const [
                DropdownMenuItem(value: 72, child: Text('72時間')),
                DropdownMenuItem(value: 48, child: Text('48時間')),
                DropdownMenuItem(value: 24, child: Text('24時間')),
                DropdownMenuItem(value: 12, child: Text('12時間')),
              ],
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFDFFFBF)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // 凡例
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('HP', const Color(0xFF00FFFF)),
                const SizedBox(width: 20),
                _buildLegendItem('MP', const Color(0xFF00FF00)),
                const SizedBox(width: 20),
                _buildLegendItem('LP', const Color(0xFFFFFF00)),
              ],
            ),
            const SizedBox(height: 30),
            // グラフ本体
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 20, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 100,
                    minX: 0,
                    maxX: selectedHours.toDouble(),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) =>
                            Colors.white.withValues(alpha: 0.9),
                        getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                          return touchedBarSpots.map((barSpot) {
                            final flSpot = barSpot;
                            String episode = '';
                            // どの線のデータか判定してエピソードを取得
                            if (barSpot.barIndex == 0)
                              episode = hpData.episodes[flSpot.spotIndex];
                            if (barSpot.barIndex == 1)
                              episode = mpData.episodes[flSpot.spotIndex];
                            if (barSpot.barIndex == 2)
                              episode = lpData.episodes[flSpot.spotIndex];
                            Color markerColor = Colors.black;
                            if (barSpot.barIndex == 0)
                              markerColor = Colors.cyan;
                            if (barSpot.barIndex == 1)
                              markerColor = Colors.green;
                            if (barSpot.barIndex == 2)
                              markerColor = Colors.yellow[700]!;

                            return LineTooltipItem(
                              '■ ',
                              TextStyle(
                                color: markerColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              children: [
                                TextSpan(
                                  text: episode,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            );
                          }).toList();
                        },
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      bottomTitles: AxisTitles(
                        axisNameWidget: Text('直近$selectedHours時間の推移'),
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: selectedHours == 12 ? 6 : 24,
                          getTitlesWidget: (value, meta) {
                            if (selectedHours == 72) {
                              if (value == 0) return const Text('3日前');
                              if (value == 24) return const Text('2日前');
                              if (value == 48) return const Text('昨日');
                              if (value == 72) return const Text('現在');
                            } else if (selectedHours == 48) {
                              if (value == 0) return const Text('2日前');
                              if (value == 24) return const Text('昨日');
                              if (value == 48) return const Text('現在');
                            } else if (selectedHours == 24) {
                              if (value == 0) return const Text('昨日');
                              if (value == 24) return const Text('現在');
                            } else if (selectedHours == 12) {
                              if (value == 0) return const Text('12時間前');
                              if (value == 6) return const Text('6時間前');
                              if (value == 12) return const Text('現在');
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: AxisTitles(
                        axisNameWidget: const Text('パーセント (%)'),
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 20,
                          getTitlesWidget: (value, meta) =>
                              Text('${value.toInt()}%'),
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: true,
                      horizontalInterval: 20,
                      verticalInterval: selectedHours == 12 ? 6 : 24,
                    ),
                    borderData: FlBorderData(
                      show: true,
                      border: Border.all(color: Colors.black12),
                    ),
                    lineBarsData: [
                      _buildLineChartBarData(
                        hpData.spots,
                        const Color(0xFF00FFFF),
                      ),
                      _buildLineChartBarData(
                        mpData.spots,
                        const Color(0xFF00FF00),
                      ),
                      _buildLineChartBarData(
                        lpData.spots,
                        const Color(0xFFFFFF00),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // AI分析エリア
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'AI分析',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '最近のHPの低下傾向が見られます。MPは安定していますが、LPに急激な変動がありましたのでストレス管理に注意してください。十分な休息をお勧めします。',
                    style: TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            Text(
              '※直近$selectedHours時間のデータを表示しています（タップで詳細を表示）',
              style: const TextStyle(color: Colors.grey, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  // 凡例のアイテムを作る
  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  // グラフの線の設定を作る
  LineChartBarData _buildLineChartBarData(List<FlSpot> spots, Color color) {
    return LineChartBarData(
      spots: spots,
      isCurved: false, // 曲線ではなく直線にする
      color: color,
      barWidth: 4,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
          radius: 4,
          color: color,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
      belowBarData: BarAreaData(
        show: false, // 塗りつぶしをしない
      ),
    );
  }
}

// --- データベース（保存）を管理するクラス ---
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('hp_app_v2.db'); // v2にして確実に初期化
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    // 現在の数値を保存するテーブル
    await db.execute('''
      CREATE TABLE status (
        id TEXT PRIMARY KEY,
        value REAL
      )
    ''');

    // 履歴を保存するテーブル
    await db.execute('''
      CREATE TABLE history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        datetime TEXT,
        episode TEXT,
        change REAL
      )
    ''');

    // 初期値の挿入
    await db.insert('status', {'id': 'hp', 'value': 80.0});
    await db.insert('status', {'id': 'mp', 'value': 80.0});
    await db.insert('status', {'id': 'lp', 'value': 80.0});
  }

  // --- 数値（HP/MP/LP）の保存と読み込み ---
  Future<void> saveStatus(String id, double value) async {
    final db = await instance.database;
    await db.insert('status', {
      'id': id.toLowerCase(),
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> getStatus(String id) async {
    final db = await instance.database;
    final maps = await db.query(
      'status',
      columns: ['value'],
      where: 'id = ?',
      whereArgs: [id.toLowerCase()],
    );

    if (maps.isNotEmpty) {
      return maps.first['value'] as double;
    }
    return 80.0;
  }

  // --- 履歴の保存と読み込み ---
  Future<void> insertHistory(String type, Map<String, dynamic> item) async {
    final db = await instance.database;
    await db.insert('history', {
      'type': type,
      'datetime': (item['datetime'] as DateTime).toIso8601String(),
      'episode': item['episode'],
      'change': item['change'],
    });
  }

  Future<List<Map<String, dynamic>>> getHistory(String type) async {
    final db = await instance.database;
    final maps = await db.query(
      'history',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'datetime DESC',
    );

    return List.generate(maps.length, (i) {
      return {
        'id': maps[i]['id'] as int,
        'type': maps[i]['type'] as String,
        'datetime': DateTime.parse(maps[i]['datetime'] as String),
        'episode': maps[i]['episode'] as String,
        'change': maps[i]['change'] as double,
      };
    });
  }

  // 履歴を削除する
  Future<void> deleteHistory(int id) async {
    final db = await database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }
}
