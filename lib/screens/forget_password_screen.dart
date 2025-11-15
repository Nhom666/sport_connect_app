import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

// --- CẤU HÌNH FIREBASE ---
// Lưu ý: Trong một ứng dụng thực tế, bạn sẽ cần file firebase_options.dart
// và hàm main() sẽ là:
/*
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
*/
// Vì đây là môi trường mô phỏng, tôi sẽ đặt hàm main đơn giản và giả định
// Firebase đã được cấu hình bên ngoài file này.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Giả định Firebase đã được khởi tạo thành công
  try {
    // Thêm dòng này để mô phỏng khởi tạo trong môi trường có thể chạy
    // Tuy nhiên, bạn CẦN thay thế bằng DefaultFirebaseOptions.currentPlatform
    // trong dự án thực của mình.
    // await Firebase.initializeApp();
  } catch (e) {
    print(
      "Warning: Firebase initialization failed. Please ensure Firebase is configured correctly in your environment.",
    );
  }
  runApp(const MyApp());
}

// --- KHAI BÁO CÁC BIẾN TOÀN CỤC ---
final FirebaseAuth _auth = FirebaseAuth.instance;

// Định nghĩa màu sắc và kiểu dáng chung cho ứng dụng
class AppColors {
  static const Color primaryBlue = Color(
    0xFF4F46E5,
  ); // Màu xanh chính (Indigo 600)
  static const Color lightBackground = Color(0xFFF8F8FA);
  static const Color titleColor = Color(0xFF1F2937);
  static const Color textColor = Color(0xFF6B7280);
  static const Color errorRed = Color(0xFFDC2626);
}

// Kiểu dáng của nút chính
final ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
  backgroundColor: AppColors.primaryBlue,
  foregroundColor: Colors.white,
  padding: const EdgeInsets.symmetric(vertical: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  elevation: 5,
  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SportConnect Reset Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: AppColors.primaryBlue,
        scaffoldBackgroundColor: AppColors.lightBackground,
        // Giả sử font Inter đã được thêm
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: const TextStyle(color: AppColors.textColor),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: AppColors.primaryBlue,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.errorRed, width: 2),
          ),
        ),
      ),
      // Giả định bạn sẽ gọi màn hình này từ màn hình Đăng nhập (Sign In)
      home: const PasswordResetFlow(),
    );
  }
}

// --- Widget Chính: Quản lý luồng chuyển màn hình ---

class PasswordResetFlow extends StatefulWidget {
  const PasswordResetFlow({super.key});

  @override
  State<PasswordResetFlow> createState() => _PasswordResetFlowState();
}

class _PasswordResetFlowState extends State<PasswordResetFlow> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _isLoading = false;
  String? _errorMessage;
  String _targetEmail = ''; // Lưu email đã gửi thành công

  // Keys và Controllers
  final _forgetPasswordFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pageController.addListener(() {
      if (_pageController.page?.round() != _currentPage) {
        setState(() {
          _currentPage = _pageController.page!.round();
          _errorMessage = null; // Xóa lỗi khi chuyển trang
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _goToNextPage() {
    if (_currentPage < 1) {
      // Chỉ có 2 trang (0 và 1)
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      // Quay về màn hình nhập email
      _pageController.previousPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      // Đóng màn hình/quay về trang đăng nhập
      Navigator.pop(context);
    }
  }

  void _showSnackbar(String message, {bool isError = true}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.errorRed : Colors.green.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // --- HÀM 1: GỬI YÊU CẦU ĐẶT LẠI MẬT KHẨU (Sử dụng Firebase Auth) ---
  Future<void> _handleSendRequest() async {
    if (!(_forgetPasswordFormKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();

      // **Sử dụng API chuẩn của Firebase Auth để gửi link đặt lại mật khẩu**
      await _auth.sendPasswordResetEmail(email: email);

      _targetEmail = email; // Lưu email để hiển thị thông báo
      _goToNextPage(); // Chuyển sang màn hình thông báo
    } on FirebaseAuthException catch (e) {
      String msg;
      if (e.code == 'user-not-found') {
        msg = 'Không tìm thấy tài khoản với email này.';
      } else if (e.code == 'invalid-email') {
        msg = 'Địa chỉ email không hợp lệ.';
      } else {
        msg = 'Lỗi gửi yêu cầu: ${e.message}';
      }
      setState(() {
        _errorMessage = msg;
      });
      _showSnackbar(msg);
    } catch (e) {
      const msg = 'Đã xảy ra lỗi không xác định.';
      setState(() {
        _errorMessage = msg;
      });
      _showSnackbar(msg);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // --- HÀM 2: GỬI LẠI YÊU CẦU ---
  Future<void> _handleResendRequest() async {
    if (_targetEmail.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Gửi lại email đặt lại mật khẩu
      await _auth.sendPasswordResetEmail(email: _targetEmail);

      _showSnackbar(
        'Đã gửi lại link đặt lại mật khẩu đến ${_targetEmail}!',
        isError: false,
      );
    } on FirebaseAuthException catch (e) {
      // Xử lý lỗi khi gửi lại
      setState(() {
        _errorMessage = 'Lỗi gửi lại yêu cầu: ${e.message}';
      });
      _showSnackbar(_errorMessage!);
    } catch (e) {
      _showSnackbar('Đã xảy ra lỗi không xác định khi gửi lại.', isError: true);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                top: 16.0,
                left: 16.0,
                right: 16.0,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _previousPage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: const Icon(
                        Icons.arrow_back,
                        color: AppColors.titleColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Hiển thị lỗi chung (nếu có)
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32.0,
                  vertical: 8.0,
                ),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(
                    color: AppColors.errorRed,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  // Màn hình 1: Nhập Email
                  _ForgetPasswordScreen(
                    formKey: _forgetPasswordFormKey,
                    emailController: _emailController,
                    onContinue: _handleSendRequest,
                    isLoading: _isLoading,
                  ),
                  // Màn hình 2: Thông báo (thay thế màn hình OTP và Reset MK)
                  _EmailConfirmationScreen(
                    email: _targetEmail,
                    onResend: _handleResendRequest,
                    onGoBack: () {
                      // **Hành động Quay về Đăng nhập đã được đặt tại đây**
                      Navigator.pop(context);
                    },
                    isLoading: _isLoading,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 40.0, top: 20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(2, (index) {
                  // CHỈ CÓ 2 DOTS
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4.0),
                    height: 8.0,
                    width: _currentPage == index ? 32.0 : 8.0,
                    decoration: BoxDecoration(
                      color: _currentPage == index
                          ? AppColors.primaryBlue
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Màn hình 1: Forget Password (Giữ nguyên) ---

class _ForgetPasswordScreen extends StatelessWidget {
  final VoidCallback onContinue;
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final bool isLoading;

  const _ForgetPasswordScreen({
    required this.onContinue,
    required this.formKey,
    required this.emailController,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 30),
            const Text(
              'Quên Mật khẩu?',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                color: AppColors.titleColor,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nhập địa chỉ email đã đăng ký để nhận link đặt lại mật khẩu.',
              style: TextStyle(fontSize: 14, color: AppColors.textColor),
            ),
            const SizedBox(height: 40),
            TextFormField(
              controller: emailController,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vui lòng nhập email.';
                }
                if (!RegExp(r'\S+@\S+\.\S+').hasMatch(value)) {
                  return 'Vui lòng nhập một địa chỉ email hợp lệ.';
                }
                return null;
              },
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(hintText: 'Email ID'),
            ),
            const SizedBox(height: 50),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : onContinue,
                style: primaryButtonStyle,
                child: isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Tiếp tục'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Màn hình 2: Thông báo xác nhận Email (ĐÃ THÊM NÚT QUAY LẠI) ---
class _EmailConfirmationScreen extends StatelessWidget {
  final String email;
  final Future<void> Function() onResend;
  final VoidCallback onGoBack; // Callback để quay về màn hình đăng nhập
  final bool isLoading;

  const _EmailConfirmationScreen({
    required this.email,
    required this.onResend,
    required this.onGoBack,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 30),
          const Text(
            'Kiểm tra Email của bạn!',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: AppColors.titleColor,
            ),
          ),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              text: 'Chúng tôi đã gửi một ',
              style: const TextStyle(fontSize: 14, color: AppColors.textColor),
              children: <TextSpan>[
                const TextSpan(
                  text: 'link đặt lại mật khẩu',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: ' đến địa chỉ email:\n\n',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textColor,
                  ),
                ),
                TextSpan(
                  text: email,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryBlue,
                  ),
                ),
                TextSpan(
                  text:
                      '\n\nVui lòng kiểm tra hộp thư đến (hoặc thư mục Spam) và nhấp vào link để đặt lại mật khẩu.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 60),
          Center(
            child: TextButton(
              onPressed: isLoading ? null : onResend,
              child: Text(
                isLoading ? 'Đang gửi lại...' : 'Gửi lại link',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isLoading
                      ? AppColors.textColor
                      : AppColors.primaryBlue,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // *** NÚT "QUAY LẠI ĐĂNG NHẬP" ĐÃ ĐƯỢC THÊM ***
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onGoBack,
              style: primaryButtonStyle.copyWith(
                backgroundColor: MaterialStateProperty.all(
                  AppColors.primaryBlue,
                ),
              ),
              child: const Text('Quay lại Đăng nhập'),
            ),
          ),
        ],
      ),
    );
  }
}
