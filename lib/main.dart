// Flutterのモバイルアプリを作るためのツール（パッケージ）を読み込みます
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'login_screen.dart';

// アプリの開始地点（メイン関数）です
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationHelper.init();
  await NotificationHelper.scheduleHealthChecks();
  runApp(const MyApp());
}

// アプリ全体の見た目や設定を決めるクラスです（StatelessWidget = 状態が変わらない画面）
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '体調記録',
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ja', 'JP')],
      locale: const Locale('ja', 'JP'),
      // アプリ全体のデザイン（テーマ）を設定します
      theme: ThemeData(
        primarySwatch: Colors.blue,
        textTheme: GoogleFonts.notoSansJpTextTheme(Theme.of(context).textTheme),
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
  final bool isAdmin; // 管理者モードで開始するかどうか
  const HPDisplayPage({super.key, required this.pageType, this.isAdmin = false});

  @override
  State<HPDisplayPage> createState() => _HPDisplayPageState();
}

// 画面の状態（データ）を管理する実体です
class _HPDisplayPageState extends State<HPDisplayPage> {
  static _HPDisplayPageState? activeInstance;

  static void triggerConditionDialog() {
    final context = navigatorKey.currentContext;
    if (context != null) {
      showConditionDialog(context);
    }
  }

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

  // --- 30分ごとHP通知用タイマー ---
  Timer? _hourlyTimer; // 定期チェック用タイマー
  String? _lastNotifiedSlot; // 最後に通知した時間帯スロット (例: "15:30")
  bool _isAdminMode = false; // 管理者モードフラグ

  @override
  void initState() {
    super.initState();
    _isAdminMode = widget.isAdmin;
    activeInstance = this;
    // データベースから保存されたデータを取り込みます
    _loadFromDatabase();
    // 1時間ごとHP通知タイマーを開始
    _startHourlyNotification();
    // アプリ起動時の通知チェック
    NotificationHelper.checkAppLaunchNotification();
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

  /// 30秒ごとに端末時刻をチェックし、7〜23時の30分ごとのスロットに
  /// まだ通知していない場合、ダイアログを表示する
  void _startHourlyNotification() {
    _hourlyTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final hour = now.hour;
      final minute = now.minute;

      // 対象時間帯: デバッグ用に7時〜23時に変更
      final isTargetHour = hour >= 7 && hour <= 23;

      // 30分単位のスロットID (例: 15:00〜15:29 は "15:0", 15:30〜15:59 は "15:30")
      final slotMinute = minute < 30 ? 0 : 30;
      final slotId = '$hour:$slotMinute';

      // すでにこのスロットで通知済みでないか
      final alreadyNotified = _lastNotifiedSlot == slotId;

      // デバッグ用のログを出力
      debugPrint(
        '【体調チェックタイマー監視】時刻: $hour時$minute分 (スロット: $slotId), 対象時間内: $isTargetHour, このスロットで通知済み: $alreadyNotified',
      );

      if (isTargetHour && !alreadyNotified) {
        debugPrint('【体調チェックダイアログ表示実行】スロット: $slotId');
        _lastNotifiedSlot = slotId;
        final context = navigatorKey.currentContext;
        if (context != null) {
          showConditionDialog(context);
        }
      }
    });
  }

  void updateHPState(
    double newValue,
    List<Map<String, dynamic>> updatedHistory,
  ) {
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
        return '体調記録';
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
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active, color: Colors.blue),
            onPressed: () async {
              await NotificationHelper.scheduleTestNotification();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '10\u79d2\u5f8c\u306e\u30c6\u30b9\u30c8\u901a\u77e5\u3092\u30b9\u30b1\u30b8\u30e5\u30fc\u30eb\u3057\u307e\u3057\u305f\u3002',
                    ), // 「10秒後のテスト通知をスケジュールしました。」
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
        ],
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
                if (_isAdminMode) ...[
                  const SizedBox(height: 25),
                  const Divider(thickness: 2, color: Colors.blueGrey),
                  const SizedBox(height: 10),
                  const Text(
                    '\u7ba1\u7406\u8005\u5c02\u7528\u30e1\u30cb\u30e5\u30fc', // 「管理者専用メニュー」
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  const SizedBox(height: 15),
                  _adminMenuButton(
                    context,
                    Icons.warning_amber_rounded,
                    Colors.red,
                    '\u4f53\u8abf\u4f4e\u4e0b\u30a2\u30e9\u30fc\u30c8\u30ea\u30b9\u30c8', // 「体調低下アラートリスト」
                    () => _showAdminAlertList(context),
                  ),
                  const SizedBox(height: 10),
                  _adminMenuButton(
                    context,
                    Icons.group_work_outlined,
                    Colors.teal,
                    '\u30b0\u30eb\u30fc\u30d7\u5225\u6bd4\u8f03\u5206\u6790', // 「グループ別比較分析」
                    () => _showAdminGroupComparison(context),
                  ),
                  const SizedBox(height: 10),
                  _adminMenuButton(
                    context,
                    Icons.analytics_outlined,
                    Colors.purple,
                    '\u8981\u56e0\u30a8\u30d4\u30bd\u30fc\u30c9\u5206\u6790', // 「要因エピソード分析」
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => EpisodeAnalysisPage(
                            hpHistory: hpEpisodeHistory,
                            otherUsers: otherUsers,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _adminMenuButton(
                    context,
                    Icons.question_answer_outlined,
                    Colors.indigo,
                    '\u30ab\u30b9\u30bf\u30e0\u8cea\u554f\u4f5c\u6210\u30fb\u914d\u4fe1', // 「カスタム質問作成・配信」
                    () async {
                      final result = await Navigator.push<Map<String, dynamic>>(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CustomQuestionEditPage(),
                        ),
                      );
                      if (result != null) {
                        final action = result['action'] as String;
                        final question = result['question'] as String;
                        final options = List<Map<String, dynamic>>.from(result['options'] as List);
                        final time = result['time'] as String;

                        if (action == 'save') {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('\u30a2\u30f3\u30b1\u30fc\u30c8\u3092\u4fdd\u5b58\u3057\u307e\u3057\u305f\u3002'), // 「アンケートを保存しました。」
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        } else if (action == 'deliver') {
                          Future.delayed(const Duration(milliseconds: 1500), () {
                            if (context.mounted) {
                              _showCustomSurveyDialog(context, question, options);
                            }
                          });
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$time \u306b\u30a2\u30f3\u30b1\u30fc\u30c8\u3092\u914d\u4fe1\u3057\u307e\u3059\u3002(\u30c6\u30b9\u30c8\u7528\u306b1.5\u79d2\u5f8c\u306e\u901a\u77e5)'), // 「XX:XXにアンケートを配信します。(テスト用に1.5秒後の通知)」
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  _adminMenuButton(
                    context,
                    Icons.download_outlined,
                    Colors.green,
                    '\u30c7\u30fc\u30bf\u30a8\u30af\u30b9\u30dd\u30fc\u30c8(CSV/PDF)', // 「データエクスポート(CSV/PDF)」
                    () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DataExportPage(
                            hpHistory: hpEpisodeHistory,
                            mpHistory: mpEpisodeHistory,
                            lpHistory: lpEpisodeHistory,
                            otherUsers: otherUsers,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _adminMenuButton(
    BuildContext context,
    IconData icon,
    Color color,
    String label,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  void _showAdminAlertList(BuildContext context) {
    final double myHP = currentHP;
    final List<Map<String, dynamic>> alerts = [
      if (myHP < 30.0) {'name': '\u81ea\u5206', 'hp': myHP, 'reason': '\u767a\u751f\u4e2d\u306e\u4e0d\u8abf'}, // 「自分」「発生中の不調」
      {'name': '\u5c71\u7530\u592a\u90ce', 'hp': 25.0, 'reason': '\u9023\u65e5\u306e\u6b8b\u696d\u306b\u3088\u308b\u75b2\u52b4'}, // 「山田太郎」「連日の残業による疲労」
      {'name': '\u4f50\u85e4\u82b1\u5b50', 'hp': 18.0, 'reason': '\u7761\u7720\u4e0d\u8db3\u3068\u982d\u75db'}, // 「佐藤花子」「睡眠不足と頭痛」
      {'name': '\u9234\u6728\u4e00\u90ce', 'hp': 29.0, 'reason': '\u7dca\u5f35\u72b6\u614b\u306e\u7d2f\u7a4d'}, // 「鈴木一郎」「緊張状態の累積」
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            '\u4f53\u8abf\u4f4e\u4e0b\u30a2\u30e9\u30fc\u30c8\u30ea\u30b9\u30c8 (HP < 30%)', // 「体調低下アラートリスト」
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: alerts.length,
              itemBuilder: (c, idx) {
                final item = alerts[idx];
                return ListTile(
                  leading: const Icon(Icons.warning, color: Colors.red),
                  title: Text('${item['name']} (HP: ${item['hp']}%)'),
                  subtitle: Text(item['reason'] as String),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }



  void _showAdminGroupComparison(BuildContext context) {
    final List<Map<String, dynamic>> groups = [
      {'name': '\u958b\u767a\u30c1\u30fc\u30e0', 'hp': 75.0, 'mp': 65.0, 'lp': 80.0}, // 「開発チーム」
      {'name': '\u55b6\u696d\u30c1\u30fc\u30e0', 'hp': 58.0, 'mp': 42.0, 'lp': 55.0}, // 「営業チーム」
      {'name': '\u4f5c\u696d\u73fe\u5834', 'hp': 82.0, 'mp': 78.0, 'lp': 88.0}, // 「作業現場」
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            '\u30b0\u30eb\u30fc\u30d7\u5225\u6bd4\u8f03\u5206\u6790 (\u5e73\u5747)', // 「グループ別比較分析（平均）」
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (c, idx) {
                final group = groups[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(group['name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text('HP: ', style: TextStyle(fontSize: 11)),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: group['hp'] / 100.0,
                              color: Colors.red,
                              backgroundColor: Colors.grey[200],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${group['hp']}%', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('MP: ', style: TextStyle(fontSize: 11)),
                          Expanded(
                            child: LinearProgressIndicator(
                              value: group['mp'] / 100.0,
                              color: Colors.blue,
                              backgroundColor: Colors.grey[200],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('${group['mp']}%', style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                      const Divider(),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }



  void _showCustomSurveyDialog(
    BuildContext context,
    String question,
    List<Map<String, dynamic>> options,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('\u30a2\u30f3\u30b1\u30fc\u30c8\u56de\u7b54'), // 「アンケート回答」
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(question, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              ...options.map((opt) {
                final String text = opt['text'] as String;
                final double value = (opt['value'] as num).toDouble();
                final String sign = value >= 0 ? '+' : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final String type = widget.pageType;
                        
                        if (type == 'HP') {
                          currentHP = (currentHP + value).clamp(0.0, 100.0);
                        } else if (type == 'MP') {
                          currentMP = (currentMP + value).clamp(0.0, 100.0);
                        } else if (type == 'LP') {
                          currentLP = (currentLP + value).clamp(0.0, 100.0);
                        }

                        final db = DatabaseHelper.instance;
                        await db.saveStatus(type.toLowerCase(), type == 'HP' ? currentHP : (type == 'MP' ? currentMP : currentLP));
                        
                        final int cleanChange = value.round();
                        final newHistoryItem = {
                          'datetime': DateTime.now().toIso8601String(),
                          'episode': '\u30a2\u30f3\u30b1\u30fc\u30c8\u56de\u7b54: $text', // 「アンケート回答: [選択肢名]」
                          'change': cleanChange,
                        };
                        await db.insertHistory(type, newHistoryItem);

                        _loadFromDatabase();

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '\u30a2\u30f3\u30b1\u30fc\u30c8\u56de\u7b54\u3092\u9069\u7528\u3057\u307e\u3057\u305f\u3002($type $sign$cleanChange%)', // 「アンケート回答を適用しました。(HP +5%)」
                              ),
                            ),
                          );
                        }
                      },
                      child: Text('$text ($sign${value.toStringAsFixed(0)}%)'),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
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
              builder: (context) => HPDisplayPage(pageType: label, isAdmin: _isAdminMode),
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
    if (activeInstance == this) {
      activeInstance = null;
    }
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

// --- 端末ローカル通知を管理するヘルパークラス ---
class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    // タイムゾーンの初期化（日本時間 Asia/Tokyo 固定）
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));

    // Android用初期化設定
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS用初期化設定
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        debugPrint('【ローカル通知タップ検知】レスポンス: ${response.payload}');
        _HPDisplayPageState.triggerConditionDialog();
      },
    );

    // Android用の通知チャンネル登録と権限要求
    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidImplementation != null) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'health_check_channel_v2',
        '\u4f53\u8abf\u8a18\u9332\u901a\u77e5', // 「体調記録通知」
        description:
            '\u5b9a\u6642\u4f53\u8abf\u5165\u529b\u306e\u30ea\u30de\u30a4\u30f3\u30c0\u30fc\u901a\u77e5', // 「定時体調入力のリマインダー通知」
        importance: Importance.max,
      );
      await androidImplementation.createNotificationChannel(channel);
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  /// アプリ起動時に通知タップによる起動か確認
  static Future<void> checkAppLaunchNotification() async {
    final details = await _notificationsPlugin
        .getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp ?? false) {
      debugPrint('【ローカル通知】通知タップによりアプリが起動されました。');
      Future.delayed(const Duration(milliseconds: 600), () {
        _HPDisplayPageState.triggerConditionDialog();
      });
    }
  }

  /// スケジュール通知の生成・最新化
  static Future<void> scheduleHealthChecks() async {
    // 既存のスケジュール通知をクリア
    await _notificationsPlugin.cancelAll();

    const AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'health_check_channel_v2',
      '\u4f53\u8abf\u8a18\u9332\u901a\u77e5', // 「体調記録通知」
      channelDescription:
          '\u5b9a\u6642\u4f53\u8abf\u5165\u529b\u306e\u30ea\u30de\u30a4\u30f3\u30c0\u30fc\u901a\u77e5', // 「定時体調入力のリマインダー通知」
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    final now = tz.TZDateTime.now(tz.local);
    debugPrint(
      '【スケジュール登録】現在時刻 JST: ${now.toString()}, タイムゾーン: ${tz.local.name}',
    );
    int notificationId = 0;

    // 今日、明日、明後日の3日間分をスケジュールする
    for (int dayOffset = 0; dayOffset < 3; dayOffset++) {
      final targetDate = now.add(Duration(days: dayOffset));

      // 10時から15時まで、1時間ごと（00分）の時刻
      for (int hour = 10; hour <= 15; hour++) {
        for (int minute in [0]) {
          final scheduledDate = tz.TZDateTime(
            tz.local,
            targetDate.year,
            targetDate.month,
            targetDate.day,
            hour,
            minute,
          );

          // 未来の時刻のみスケジュール
          if (scheduledDate.isAfter(now)) {
            try {
              await _notificationsPlugin.zonedSchedule(
                id: notificationId++,
                title: '\u4f53\u8abf\u8a18\u9332', // 「体調記録」
                body:
                    '\u4eca\u306e\u4f53\u8abf\u306f\u3069\u3046\u3067\u3059\u304b\uff1f', // 「今の体調はどうですか？」
                scheduledDate: scheduledDate,
                notificationDetails: notificationDetails,
                androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              );
              debugPrint(
                '【通知スケジュール成功】ID: ${notificationId - 1}, 予定時刻 JST: ${scheduledDate.toString()}',
              );
            } catch (e) {
              await _notificationsPlugin.zonedSchedule(
                id: notificationId++,
                title: '\u4f53\u8abf\u8a18\u9332', // 「体調記録」
                body:
                    '\u4eca\u306e\u4f53\u8abf\u306f\u3069\u3046\u3067\u3059\u304b\uff1f', // 「今の体調はどうですか？」
                scheduledDate: scheduledDate,
                notificationDetails: notificationDetails,
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              );
              debugPrint(
                '【通知スケジュールフォールバック】ID: ${notificationId - 1}, 予定時刻 JST: ${scheduledDate.toString()}',
              );
            }
          }
        }
      }
    }
    debugPrint('【ローカル通知】合計 $notificationId 件の通知をスケジュールしました。');
  }

  /// テスト用の10秒後通知スケジュール関数
  static Future<void> scheduleTestNotification() async {
    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = now.add(const Duration(seconds: 10));

    const AndroidNotificationDetails
    androidDetails = AndroidNotificationDetails(
      'health_check_channel_v2',
      '\u4f53\u8abf\u8a18\u9332\u901a\u77e5',
      channelDescription:
          '\u5b9a\u6642\u4f53\u8abf\u5165\u529b\u306e\u30ea\u30de\u30a4\u30f3\u30c0\u30fc\u901a\u77e5',
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.alarm,
    );

    await _notificationsPlugin.zonedSchedule(
      id: 9999,
      title:
          '\u3010\u30c6\u30b9\u30c8\u3011\u4f53\u8abf\u8a18\u9332', // 「【テスト】体調記録」
      body:
          '10\u79d2\u5f8c\u306e\u30c6\u30b9\u30c8\u901a\u77e5\u3067\u3059\u3002', // 「10秒後のテスト通知です。」
      scheduledDate: scheduledDate,
      notificationDetails: const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    debugPrint('【テスト通知スケジュール】10秒後にスケジュール登録完了 JST: ${scheduledDate.toString()}');
  }
}

// --- 統一された体調確認ダイアログの表示ヘルパー ---
void showConditionDialog(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false, // 必ずボタンを選んで閉じる
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.favorite, color: Color(0xFF00FFFF)),
            SizedBox(width: 8),
            Text(
              '\u4eca\u306e\u4f53\u8abf\u306f\u3069\u3046\u3067\u3059\u304b\uff1f', // 「今の体調はどうですか？」
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _conditionButtonGlobal(
              ctx,
              '\u826f\u3044',
              const Color(0xFFE53935),
              5.0,
            ), // 良い (赤)
            const SizedBox(height: 8),
            _conditionButtonGlobal(
              ctx,
              '\u5c11\u3057\u826f\u3044',
              const Color(0xFFD81B60),
              3.0,
            ), // 少し良い (マゼンタ)
            const SizedBox(height: 8),
            _conditionButtonGlobal(
              ctx,
              '\u666e\u901a',
              const Color(0xFF90A4AE),
              0.0,
            ), // 普通 (ブルーグレー)
            const SizedBox(height: 8),
            _conditionButtonGlobal(
              ctx,
              '\u5c11\u3057\u60aa\u3044',
              const Color(0xFF5E35B1),
              -3.0,
            ), // 少し悪い (青紫)
            const SizedBox(height: 8),
            _conditionButtonGlobal(
              ctx,
              '\u60aa\u3044',
              const Color(0xFF311B92),
              -5.0,
            ), // 悪い (暗い紫)
          ],
        ),
      );
    },
  );
}

Widget _conditionButtonGlobal(
  BuildContext ctx,
  String label,
  Color color,
  double delta,
) {
  return SizedBox(
    width: double.infinity,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      onPressed: () {
        Navigator.of(ctx).pop(); // ダイアログを閉じる
        _applyConditionChangeGlobal(delta);
      },
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

/// グローバルなHP更新・履歴追加関数
Future<void> _applyConditionChangeGlobal(double delta) async {
  final double currentHP = _HPDisplayPageState.currentHP;
  final double newValue = (currentHP + delta).clamp(0.0, 100.0);

  final db = DatabaseHelper.instance;
  await db.saveStatus('HP', newValue);

  final newHistoryItem = {
    'datetime': DateTime.now(),
    'episode': '\u5b9a\u6642\u5165\u529b', // 「定時入力」
    'change': delta,
  };
  await db.insertHistory('HP', newHistoryItem);

  final updatedHistory = await db.getHistory('HP');

  if (_HPDisplayPageState.activeInstance != null &&
      _HPDisplayPageState.activeInstance!.mounted) {
    _HPDisplayPageState.activeInstance!.updateHPState(newValue, updatedHistory);
  } else {
    _HPDisplayPageState.currentHP = newValue;
    _HPDisplayPageState.hpEpisodeHistory = updatedHistory;
  }
}


// ============================================================================
// CustomQuestionEditPage (カスタムアンケートの作成・一時ストック・再編集画面)
// ============================================================================

class CustomQuestionEditPage extends StatefulWidget {
  const CustomQuestionEditPage({super.key});

  @override
  State<CustomQuestionEditPage> createState() => _CustomQuestionEditPageState();
}

class _CustomQuestionEditPageState extends State<CustomQuestionEditPage> {
  final TextEditingController _questionController = TextEditingController();
  
  final TextEditingController _option1Controller = TextEditingController(text: '\u306f\u3044'); // 「はい」
  final TextEditingController _option2Controller = TextEditingController(text: '\u3069\u3061\u3089\u3067\u3082\u306a\u3044'); // 「どちらでもない」
  final TextEditingController _option3Controller = TextEditingController(text: '\u3044\u3044\u3048'); // 「いいえ」

  final TextEditingController _value1Controller = TextEditingController(text: '5');
  final TextEditingController _value2Controller = TextEditingController(text: '0');
  final TextEditingController _value3Controller = TextEditingController(text: '-5');

  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 30);

  // 保存されたアンケートの一時ストックリスト
  final List<Map<String, dynamic>> _savedSurveys = [];

  @override
  void dispose() {
    _questionController.dispose();
    _option1Controller.dispose();
    _option2Controller.dispose();
    _option3Controller.dispose();
    _value1Controller.dispose();
    _value2Controller.dispose();
    _value3Controller.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  // フォームの内容を一時保存リストにストックする
  void _saveSurveyLocally() {
    final String questionText = _questionController.text.trim();
    if (questionText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u8cea\u554f\u5185\u5bb9\u304c\u5165\u529b\u3055\u308c\u3066\u3044\u307e\u305b\u3093', // 「質問内容が入力されていません」
          ),
        ),
      );
      return;
    }

    final double val1 = double.tryParse(_value1Controller.text) ?? 5.0;
    final double val2 = double.tryParse(_value2Controller.text) ?? 0.0;
    final double val3 = double.tryParse(_value3Controller.text) ?? -5.0;
    final String timeStr = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    setState(() {
      _savedSurveys.add({
        'question': questionText,
        'options': [
          {'text': _option1Controller.text.trim(), 'value': val1},
          {'text': _option2Controller.text.trim(), 'value': val2},
          {'text': _option3Controller.text.trim(), 'value': val3},
        ],
        'time': timeStr,
      });

      // フォームをクリアして初期化
      _questionController.clear();
      _option1Controller.text = '\u306f\u3044';
      _option2Controller.text = '\u3069\u3061\u3089\u3067\u3082\u306a\u3044';
      _option3Controller.text = '\u3044\u3044\u3048';
      _value1Controller.text = '5';
      _value2Controller.text = '0';
      _value3Controller.text = '-5';
      _selectedTime = const TimeOfDay(hour: 9, minute: 30);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u30a2\u30f3\u30b1\u30fc\u30c8\u3092\u4e00\u6642\u4fdd\u5b58\u3057\u307e\u3057\u305f', // 「アンケートを一時保存しました」
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // 入力フォームの現在の内容で直接配信する
  void _deliverDirectly() {
    final String questionText = _questionController.text.trim();
    if (questionText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u8cea\u554f\u5185\u5bb9\u304c\u5165\u529b\u3055\u308c\u3066\u3044\u307e\u305b\u3093', // 「質問内容が入力されていません」
          ),
        ),
      );
      return;
    }

    final double val1 = double.tryParse(_value1Controller.text) ?? 5.0;
    final double val2 = double.tryParse(_value2Controller.text) ?? 0.0;
    final double val3 = double.tryParse(_value3Controller.text) ?? -5.0;
    final String timeStr = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    Navigator.pop(context, {
      'action': 'deliver',
      'question': questionText,
      'options': [
        {'text': _option1Controller.text.trim(), 'value': val1},
        {'text': _option2Controller.text.trim(), 'value': val2},
        {'text': _option3Controller.text.trim(), 'value': val3},
      ],
      'time': timeStr,
    });
  }

  // 保存済みリストのアイテムを再編集用に入力フォームに書き戻す
  void _editSurvey(int index) {
    final survey = _savedSurveys[index];
    final options = survey['options'] as List;
    
    setState(() {
      _questionController.text = survey['question'] as String;
      
      _option1Controller.text = options[0]['text'] as String;
      _value1Controller.text = (options[0]['value'] as num).toStringAsFixed(0);

      _option2Controller.text = options[1]['text'] as String;
      _value2Controller.text = (options[1]['value'] as num).toStringAsFixed(0);

      _option3Controller.text = options[2]['text'] as String;
      _value3Controller.text = (options[2]['value'] as num).toStringAsFixed(0);

      final parts = (survey['time'] as String).split(':');
      _selectedTime = TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));

      // リストから一旦削除
      _savedSurveys.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final String timeLabel = '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('\u30ab\u30b9\u30bf\u30e0\u8cea\u554f\u7de8\u96c6'), // 「カスタム質問編集」
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFDFFFBF),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u30a2\u30f3\u30b1\u30fc\u30c8\u4f5c\u6210', // 「アンケート作成」
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.indigo,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        '\u8cea\u554f\u5185\u5bb9', // 「質問内容」
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _questionController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: '\u4f53\u8abf\u3084\u75b2\u52b4\u306b\u95a2\u3059\u308b\u8cea\u554f\u3092\u5165\u529b\u3057\u3066\u306d', // 「体調や疲労に関する質問を入力してね」
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildOptionRow('\u9078\u629e\u80a21', _option1Controller, _value1Controller),
                      const SizedBox(height: 16),
                      _buildOptionRow('\u9078\u629e\u80a22', _option2Controller, _value2Controller),
                      const SizedBox(height: 16),
                      _buildOptionRow('\u9078\u629e\u80a23', _option3Controller, _value3Controller),
                      const SizedBox(height: 24),
                      
                      // 投稿時刻設定
                      const Text(
                        '\u6295\u7a3f\u6642\u523b\u0020\u0028\u30d7\u30c3\u30b7\u30e5\u6642\u523b\u0029', // 「投稿時刻 (プッシュ時刻)」
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Text(
                              timeLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: _pickTime,
                            icon: const Icon(Icons.access_time, size: 18),
                            label: const Text('\u6642\u523b\u3092\u9078\u629e\u3059\u308b'), // 「時刻を選択する」
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo.withAlpha(25),
                              foregroundColor: Colors.indigo,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // 保存ボタン（一時リストに追加）
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _saveSurveyLocally,
                  icon: const Icon(Icons.save_rounded, color: Colors.blueGrey),
                  label: const Text(
                    '\u4fdd\u5b58\u0020\u0028\u5b9f\u884c\u305b\u305a\u306b\u4fdd\u5b58\u3059\u308b\u0029', // 「保存 (実行せずに保存する)」
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blueGrey,
                    side: const BorderSide(color: Colors.blueGrey, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 一時保存リスト（アコーディオンタイル）の表示部分
              if (_savedSurveys.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    '\u4fdd\u5b58\u6e08\u307f\u30a2\u30f3\u30b1\u30fc\u30c8\u0020\u0028\u4e00\u6642\u30b9\u30c8\u30c3\u30af\u0029', // 「保存済みアンケート (一時ストック)」
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                  ),
                ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _savedSurveys.length,
                  itemBuilder: (context, idx) {
                    final survey = _savedSurveys[idx];
                    final listOptions = survey['options'] as List;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: ExpansionTile(
                        leading: const Icon(Icons.description_outlined, color: Colors.indigo),
                        title: Text(
                          survey['question'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          '\u23f1\u0020\u6295\u7a3f\u0020${survey['time']}', // 「⏰ 投稿 XX:XX」
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(),
                                ...listOptions.map((opt) {
                                  final double val = (opt['value'] as num).toDouble();
                                  final String sign = val >= 0 ? '+' : '';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.circle, size: 6, color: Colors.indigo),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${opt['text']}: $sign${val.toStringAsFixed(0)}%',
                                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                                const SizedBox(height: 12),
                                // アクションテキストボタン群（右下配置）
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _savedSurveys.removeAt(idx);
                                        });
                                      },
                                      child: const Text(
                                        '\u524a\u9664', // 「削除」
                                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () => _editSurvey(idx),
                                      child: const Text(
                                        '\u7de8\u96c6', // 「編集」
                                        style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(context, {
                                          'action': 'deliver',
                                          'question': survey['question'] as String,
                                          'options': survey['options'],
                                          'time': survey['time'] as String,
                                        });
                                      },
                                      child: const Text(
                                        '\u914d\u4fe1', // 「配信」
                                        style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),

              // 配信ボタン（現在のフォームの内容で即座に配信する用）
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _deliverDirectly,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: const Text(
                    '\u30a2\u30f3\u30b1\u30fc\u30c8\u3092\u914d\u4fe1\u3059\u308b', // 「アンケートを配信する」
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionRow(
    String label,
    TextEditingController textCtrl,
    TextEditingController valCtrl,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: textCtrl,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 1,
              child: TextField(
                controller: valCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: InputDecoration(
                  suffixText: '%',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}


// ============================================================================
// DataExportPage (データ分析・エクスポート画面。ユーザー一覧切り替え、折れ線グラフ、CSVログ出力)
// ============================================================================

class DataExportPage extends StatefulWidget {
  final List<Map<String, dynamic>> hpHistory;
  final List<Map<String, dynamic>> mpHistory;
  final List<Map<String, dynamic>> lpHistory;
  final List<Map<String, dynamic>> otherUsers;

  const DataExportPage({
    super.key,
    required this.hpHistory,
    required this.mpHistory,
    required this.lpHistory,
    required this.otherUsers,
  });

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  String _selectedUser = '\u81ea\u5206'; // 「自分」

  // 選択されたユーザーに対応する履歴（HP, MP, LP）を取得またはシミュレート生成する
  Map<String, List<Map<String, dynamic>>> _getActiveHistories() {
    if (_selectedUser == '\u81ea\u5206') {
      return {
        'hp': widget.hpHistory,
        'mp': widget.mpHistory,
        'lp': widget.lpHistory,
      };
    }

    // 他ユーザーの現在のステータスから逆算してシミュレーションデータを構築
    final user = widget.otherUsers.firstWhere(
      (u) => u['name'] == _selectedUser,
      orElse: () => {
        'name': _selectedUser,
        'hp': 80.0,
        'mp': 80.0,
        'lp': 80.0,
      },
    );

    final double curHP = (user['hp'] as num).toDouble();
    final double curMP = (user['mp'] as num).toDouble();
    final double curLP = (user['lp'] as num).toDouble();

    // 過去5時間のエピソード逆算モック
    final List<Map<String, dynamic>> mockHP = [
      {'datetime': DateTime.now().subtract(const Duration(hours: 4)), 'episode': '\u5b9a\u6642\u5165\u529b', 'change': 10}, // 「定時入力」
      {'datetime': DateTime.now().subtract(const Duration(hours: 3)), 'episode': '\u4f5c\u696d\u958b\u59cb', 'change': 5}, // 「作業開始」
      {'datetime': DateTime.now().subtract(const Duration(hours: 2)), 'episode': '\u663c\u4f11\u307f', 'change': 15}, // 「昼休み」
      {'datetime': DateTime.now().subtract(const Duration(hours: 1)), 'episode': '\u7dca\u5f35\u306e\u7d2f\u7a4d', 'change': -15}, // 「緊張の累積」
      {'datetime': DateTime.now(), 'episode': '\u5b9a\u6642\u5165\u529b', 'change': (curHP - 95.0).round()}, // 現在の値に合わせるための調整
    ];

    final List<Map<String, dynamic>> mockMP = [
      {'datetime': DateTime.now().subtract(const Duration(hours: 4)), 'episode': '\u5b9a\u6642\u5165\u529b', 'change': 5},
      {'datetime': DateTime.now().subtract(const Duration(hours: 3)), 'episode': '\u6253\u3061\u5408\u308f\u305b', 'change': -10}, // 「打ち合わせ」
      {'datetime': DateTime.now().subtract(const Duration(hours: 2)), 'episode': '\u663c\u4f11\u307f', 'change': 10},
      {'datetime': DateTime.now().subtract(const Duration(hours: 1)), 'episode': '\u75b2\u52b4\u306e\u84c4\u7a4d', 'change': -5}, // 「疲労の蓄積」
      {'datetime': DateTime.now(), 'episode': '\u5b9a\u6642\u5165\u529b', 'change': (curMP - 80.0).round()},
    ];

    final List<Map<String, dynamic>> mockLP = [
      {'datetime': DateTime.now().subtract(const Duration(hours: 4)), 'episode': '\u5b9a\u6642\u5165\u529b', 'change': 10},
      {'datetime': DateTime.now().subtract(const Duration(hours: 3)), 'episode': '\u4f5c\u696d\u958b\u59cb', 'change': 5},
      {'datetime': DateTime.now().subtract(const Duration(hours: 2)), 'episode': '\u663c\u4f11\u307f', 'change': 10},
      {'datetime': DateTime.now().subtract(const Duration(hours: 1)), 'episode': '\u75b2\u52b4\u306e\u84c4\u7a4d', 'change': -10},
      {'datetime': DateTime.now(), 'episode': '\u5b9a\u6642\u5165\u529b', 'change': (curLP - 95.0).round()},
    ];

    return {
      'hp': mockHP,
      'mp': mockMP,
      'lp': mockLP,
    };
  }

  List<FlSpot> _getSpots(List<Map<String, dynamic>> history, double initialValue) {
    if (history.isEmpty) {
      return [
        const FlSpot(0, 80),
        const FlSpot(1, 75),
        const FlSpot(2, 85),
        const FlSpot(3, 70),
        const FlSpot(4, 90),
      ];
    }
    final sorted = List<Map<String, dynamic>>.from(history);
    sorted.sort((a, b) => (a['datetime'] as DateTime).compareTo(b['datetime'] as DateTime));
    
    List<FlSpot> spots = [];
    double currentVal = initialValue;
    spots.add(FlSpot(0, currentVal));
    
    for (int i = 0; i < sorted.length; i++) {
      final double change = (sorted[i]['change'] as num).toDouble();
      currentVal = (currentVal + change).clamp(0.0, 100.0);
      spots.add(FlSpot((i + 1).toDouble(), currentVal));
    }
    return spots;
  }

  String _generateCSV(
    List<Map<String, dynamic>> hp,
    List<Map<String, dynamic>> mp,
    List<Map<String, dynamic>> lp,
  ) {
    final List<Map<String, dynamic>> all = [];
    for (var h in hp) {
      all.add({...h, 'type': 'HP'});
    }
    for (var m in mp) {
      all.add({...m, 'type': 'MP'});
    }
    for (var l in lp) {
      all.add({...l, 'type': 'LP'});
    }
    all.sort((a, b) => (a['datetime'] as DateTime).compareTo(b['datetime'] as DateTime));
    
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('datetime,user,type,episode,change');
    for (var row in all) {
      final DateTime dt = row['datetime'] as DateTime;
      final timeStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      buffer.writeln('"$timeStr","$_selectedUser","${row['type']}","${row['episode']}",${row['change']}%');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final histories = _getActiveHistories();
    final hpList = histories['hp']!;
    final mpList = histories['mp']!;
    final lpList = histories['lp']!;

    final hpSpots = _getSpots(hpList, 80.0);
    final mpSpots = _getSpots(mpList, 80.0);
    final lpSpots = _getSpots(lpList, 80.0);
    
    final csvText = _generateCSV(hpList, mpList, lpList);
    final bool isSample = hpList.isEmpty && mpList.isEmpty && lpList.isEmpty;

    // ユーザー選択肢リストの作成
    final List<String> userOptions = [
      '\u81ea\u5206', // 「自分」
      ...widget.otherUsers.map((u) => u['name'] as String),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('\u30c7\u30fc\u30bf\u5206\u6790\u30fb\u30a8\u30af\u30b9\u30dd\u30fc\u30c8'), // 「データ分析・エクスポート」
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFDFFFBF),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ユーザー選択プルダウン（Body最上部）
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_search_rounded, color: Colors.blueGrey),
                          SizedBox(width: 8),
                          Text(
                            '\u5bfe\u8c61\u30e5\u30fc\u30b6\u30fc', // 「対象ユーザー」
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      DropdownButton<String>(
                        value: _selectedUser,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                        style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                        underline: Container(height: 1.5, color: Colors.blueGrey),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedUser = newValue;
                            });
                          }
                        },
                        items: userOptions.map((String user) {
                          return DropdownMenuItem<String>(
                            value: user,
                            child: Text(user),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // グラフカード
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u30a8\u30cd\u30eb\u30ae\u30fc\u63a8\u79fb\u30b0\u30e9\u30d5 (HP/MP/LP)', // 「エネルギー推移グラフ (HP/MP/LP)」
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (isSample)
                        const Text(
                          '\u203b\u30c7\u30fc\u30bf\u304c\u306a\u3044\u5834\u5408\u306f\u30b5\u30f3\u30d7\u30eb\u63a8\u79fb\u3092\u8868\u793a\u3057\u3066\u3044\u307e\u3059', // 「※データがない場合はサンプル推移を表示しています」
                          style: TextStyle(fontSize: 11, color: Colors.red),
                        ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 220,
                        child: LineChart(
                          LineChartData(
                            minY: 0,
                            maxY: 100,
                            lineBarsData: [
                              LineChartBarData(
                                spots: hpSpots,
                                isCurved: true,
                                color: Colors.red,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                              ),
                              LineChartBarData(
                                spots: mpSpots,
                                isCurved: true,
                                color: Colors.blue,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                              ),
                              LineChartBarData(
                                spots: lpSpots,
                                isCurved: true,
                                color: Colors.purple,
                                barWidth: 3,
                                dotData: const FlDotData(show: true),
                              ),
                            ],
                            titlesData: const FlTitlesData(
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildIndicator('HP', Colors.red),
                          const SizedBox(width: 15),
                          _buildIndicator('MP', Colors.blue),
                          const SizedBox(width: 15),
                          _buildIndicator('LP', Colors.purple),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // CSV出力カード
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u0043\u0053\u0056\u30a8\u30af\u30b9\u30dd\u30fc\u30c8\u30ed\u30b0', // 「CSVエクスポートログ」
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 180),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            csvText,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: csvText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '\u30af\u30ea\u30c3\u30d7\u30dc\u30fc\u30c9\u306b\u30b3\u30d4\u30fc\u3057\u307e\u3057\u305f', // 「クリップボードにコピーしました」
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy_rounded, color: Colors.white),
                          label: const Text(
                            '\u0043\u0053\u0056\u3092\u30af\u30ea\u30c3\u30d7\u30dc\u30fc\u30c9\u306b\u30b3\u30d4\u30fc', // 「CSVをクリップボードにコピー」
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIndicator(String text, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}


// ============================================================================
// EpisodeAnalysisPage (要因分析画面。ユーザー一覧切り替え、疲弊要因のインジケータ表示)
// ============================================================================

class EpisodeAnalysisPage extends StatefulWidget {
  final List<Map<String, dynamic>> hpHistory;
  final List<Map<String, dynamic>> otherUsers;

  const EpisodeAnalysisPage({
    super.key,
    required this.hpHistory,
    required this.otherUsers,
  });

  @override
  State<EpisodeAnalysisPage> createState() => _EpisodeAnalysisPageState();
}

class _EpisodeAnalysisPageState extends State<EpisodeAnalysisPage> {
  String _selectedUser = '\u81ea\u5206'; // 「自分」

  Map<String, int> _getAnalysisData() {
    if (_selectedUser == '\u81ea\u5206') {
      final Map<String, int> counts = {};
      for (var history in widget.hpHistory) {
        final double change = (history['change'] as num).toDouble();
        if (change < 0) {
          final String ep = history['episode'] as String;
          counts[ep] = (counts[ep] ?? 0) + 1;
        }
      }
      if (counts.isEmpty) {
        counts['\u6b8b\u696d'] = 4; // 残業
        counts['\u7761\u7720\u4e0d\u8db3'] = 3; // 睡眠不足
        counts['\u982d\u75db'] = 2; // 頭痛
      }
      return counts;
    } else if (_selectedUser.contains('\u7530\u4e2d')) { // 田中 太郎
      return {
        '\u6b8b\u696d': 6, // 残業
        '\u9832\u307f\u904e\u304e': 3, // 飲み過ぎ
        '\u7761\u7720\u4e0d\u8db3': 2, // 睡眠不足
      };
    } else if (_selectedUser.contains('\u4f50\u85e4')) { // 佐藤 花子
      return {
        '\u4f1a\u8b70\u75b2\u308c': 5, // 会議疲れ
        '\u982d\u75db': 3, // 頭痛
        '\u76ee\u306e\u75b2\u308c': 2, // 目の疲れ
      };
    } else if (_selectedUser.contains('\u9234\u6728')) { // 鈴木 一郎
      return {
        '\u529b\u4ed5\u4e8b': 7, // 力仕事
        '\u7b4b\u8089\u75db': 4, // 筋肉痛
        '\u6e80\u54e1\u96fb\u8eca': 2, // 満員電車
      };
    } else {
      return {
        '\u6b8b\u696d': 3,
        '\u76ee\u306e\u75b2\u308c': 2,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final counts = _getAnalysisData();
    final List<String> userOptions = [
      '\u81ea\u5206', // 「自分」
      ...widget.otherUsers.map((u) => u['name'] as String),
    ];

    final int maxVal = counts.values.isEmpty
        ? 1
        : counts.values.reduce((curr, next) => curr > next ? curr : next);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('\u8981\u56e0\u5206\u6790'), // 「要因分析」
        centerTitle: true,
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFFFF),
              Color(0xFFDFFFBF),
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ユーザー選択カード
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.person_search_rounded, color: Colors.blueGrey),
                          SizedBox(width: 8),
                          Text(
                            '\u5bfe\u8c61\u30e5\u30fc\u30b6\u30fc', // 「対象ユーザー」
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ],
                      ),
                      DropdownButton<String>(
                        value: _selectedUser,
                        icon: const Icon(Icons.arrow_drop_down, color: Colors.blueGrey),
                        style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),
                        underline: Container(height: 1.5, color: Colors.blueGrey),
                        onChanged: (String? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _selectedUser = newValue;
                            });
                          }
                        },
                        items: userOptions.map((String user) {
                          return DropdownMenuItem<String>(
                            value: user,
                            child: Text(user),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // 分析詳細カード
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '\u4e0d\u8abf\u306e\u4e3b\u8981\u539f\u56e0\u0020\u0028\u75b2\u5f0a\u8981\u56e0\u306e\u5206\u6795\u0029', // 「不調の主要原因 (疲弊要因の分析)」
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ...counts.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    entry.key,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${entry.value} \u56de', // 「回」
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.purple,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: entry.value / maxVal.toDouble(),
                                backgroundColor: Colors.grey[200],
                                color: Colors.purple,
                                minHeight: 12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
