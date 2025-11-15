import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sign_up_screen.dart';
import 'package:sport_connect_app/service/auth_service.dart'; // <-- IMPORT AUTH SERVICE
import 'forget_password_screen.dart'; // <-- IMPORT PASSWORD RESET FLOW
import 'package:sport_connect_app/main.dart'; // <-- IMPORT MAIN SCREEN

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final TextEditingController _emailController = TextEditingController(
    text: '',
  );
  final TextEditingController _passwordController = TextEditingController(
    text: '',
  );
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  // --- THÊM DÒNG NÀY ---
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Hàm xử lý Đăng nhập Email/Password
  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      // MỚI: Gọi hàm để lưu/cập nhật thông tin người dùng vào Firestore
      if (userCredential.user != null) {
        await _authService.saveUserToFirestore(userCredential.user!);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng nhập thành công!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainScreen()),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đăng nhập thất bại: ${e.message}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --- THÊM HÀM NÀY ---
  // Hàm xử lý đăng nhập bằng nhà cung cấp (Google/Facebook)
  Future<void> _signInWithProvider(
    Future<UserCredential?> Function() signInMethod,
  ) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await signInMethod();
      if (userCredential != null) {
        if (!mounted) return;

        // Hiển thị thông báo thành công
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đăng nhập thành công!'),
            backgroundColor: Colors.green,
          ),
        );

        // Chuyển sang MainScreen và loại bỏ tất cả các route trước đó
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đăng nhập thất bại: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: screenHeight * 0.08),

              const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Connect your match, match your sport.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              SizedBox(height: screenHeight * 0.05),

              // --- CẬP NHẬT Ở ĐÂY ---
              _buildSocialLoginButtons(context),
              const SizedBox(height: 30),

              _buildOrDivider(),
              const SizedBox(height: 30),

              _buildInputField(
                hintText: 'Email/Phone Number',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              _buildPasswordField(
                hintText: 'Password',
                controller: _passwordController,
              ),
              const SizedBox(height: 10),

              Align(
                alignment: Alignment.centerRight,
                child: _buildForgetPasswordLink(),
              ),
              const SizedBox(height: 30),

              _buildLoginButton(context),
              SizedBox(height: screenHeight * 0.05),

              _buildSignUpLink(),
              SizedBox(height: screenHeight * 0.02),
            ],
          ),
        ),
      ),
    );
  }

  // --- CẬP NHẬT WIDGET NÀY ---
  Widget _buildSocialLoginButtons(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _SocialButton(
            label: 'Facebook',
            icon: Icons.facebook,
            color: Colors.blue[700]!,
            onPressed: _isLoading
                ? null
                : () => _signInWithProvider(_authService.signInWithFacebook),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _SocialButton(
            label: 'Google',
            icon: Icons.g_mobiledata,
            color: Colors.red[600]!,
            isGoogle: true,
            onPressed: _isLoading
                ? null
                : () => _signInWithProvider(_authService.signInWithGoogle),
          ),
        ),
      ],
    );
  }

  // --- CÁC WIDGET KHÁC GIỮ NGUYÊN ---
  Widget _buildInputField({
    required String hintText,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hintText,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 20,
          ),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String hintText,
    required TextEditingController controller,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        obscureText: !_isPasswordVisible,
        decoration: InputDecoration(
          hintText: hintText,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 20,
          ),
          border: InputBorder.none,
          suffixIcon: IconButton(
            icon: Icon(
              _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
              color: Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _isPasswordVisible = !_isPasswordVisible;
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _buildLoginButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3F51B5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 5,
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text(
                'Log In',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildSignUpLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Text(
          "Don't have account? ",
          style: TextStyle(fontSize: 15, color: Colors.black87),
        ),
        InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const SignUpScreen()),
            );
          },
          child: const Text(
            'Sign Up',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF3F51B5),
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: Colors.grey, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Text(
            'Or',
            style: TextStyle(
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Expanded(child: Divider(color: Colors.grey, thickness: 1)),
      ],
    );
  }

  Widget _buildForgetPasswordLink() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PasswordResetFlow()),
        );
      },
      child: Text(
        'Forget Password?',
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey[600],
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// --- CẬP NHẬT WIDGET _SocialButton ---
class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isGoogle;
  final VoidCallback? onPressed; // Thêm callback

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.color,
    this.isGoogle = false,
    this.onPressed, // Thêm vào constructor
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      ),
      child: TextButton(
        onPressed: onPressed, // Sử dụng callback
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            isGoogle
                ? const Text(
                    'G',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(color: Colors.grey[700], fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
