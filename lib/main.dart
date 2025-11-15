import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:circle_nav_bar/circle_nav_bar.dart';
import 'screens/home.dart';
import 'screens/sign_in_screen.dart';
import 'screens/discover_screen.dart';
import 'screens/list_box_chat.dart';
import 'screens/team_screen.dart' hide kAccentColor;
import 'screens/schedule_screen.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'utils/constants.dart';
import 'package:intl/date_symbol_data_local.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // KHỞI TẠO FIREBASE
  await Firebase.initializeApp();

  await FirebaseAppCheck.instance.activate(
    // Bạn có thể chọn nhà cung cấp phù hợp cho Android/iOS
    androidProvider: AndroidProvider.playIntegrity,
    // appleProvider: AppleProvider.appAttest, // Dành cho iOS
  );
  await initializeDateFormatting('vi_VN', null);

  runApp(const SportConnectApp());
}

class SportConnectApp extends StatelessWidget {
  const SportConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SportConnect',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const AuthWrapper(),
    );
  }
}

// ----------------------------------------------------
// WIDGET QUẢN LÝ LUỒNG XÁC THỰC
// ----------------------------------------------------

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Sử dụng StreamBuilder để lắng nghe thay đổi trạng thái đăng nhập từ Firebase
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Nếu đang tải (chưa biết trạng thái)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. Nếu người dùng đã đăng nhập (User != null)
        if (snapshot.hasData && snapshot.data != null) {
          // Trả về màn hình chính có Bottom Navigation Bar
          return const MainScreen();
        }
        // 3. Nếu người dùng chưa đăng nhập (User == null)
        else {
          // Trả về màn hình Đăng nhập (hoặc Đăng ký)
          return const SignInScreen();
        }
      },
    );
  }
}

// ----------------------------------------------------
// MAIN SCREEN (ANIMATED NOTCH BOTTOM NAVIGATION)
// ----------------------------------------------------
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  /// Controller to handle PageView and also handles initial page
  final _pageController = PageController(initialPage: 0);

  int _currentIndex = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  /// Widget list
  final List<Widget> bottomBarPages = [
    const HomeScreen(),
    const DiscoverScreen(),
    const ListBoxChatScreen(),
    const TeamScreen(),
    const ScheduleScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: bottomBarPages,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
      ),
      bottomNavigationBar: CircleNavBar(
        activeIcons: [
          Icon(Icons.home, color: Colors.white, size: 25),
          Icon(Icons.explore, color: Colors.white, size: 25),
          Icon(Icons.chat, color: Colors.white, size: 25),
          Icon(Icons.people_alt, color: Colors.white, size: 25),
          Icon(Icons.schedule, color: Colors.white, size: 25),
        ],
        inactiveIcons: [
          Icon(Icons.home_outlined, color: Colors.grey.shade600, size: 24),
          Icon(Icons.explore_outlined, color: Colors.grey.shade600, size: 24),
          Icon(Icons.chat, color: Colors.grey.shade600, size: 24),
          Icon(
            Icons.people_alt_outlined,
            color: Colors.grey.shade600,
            size: 24,
          ),
          Icon(Icons.schedule_outlined, color: Colors.grey.shade600, size: 24),
        ],
        color: Colors.white,
        circleColor: kAccentColor,
        activeIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          _pageController.jumpToPage(index);
        },
        padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
        cornerRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(24),
          bottomLeft: Radius.circular(24),
        ),
        shadowColor: Colors.black,
        elevation: 10,
        tabCurve: Curves.easeInOut,
        iconCurve: Curves.bounceInOut,
      ),
    );
  }
}
