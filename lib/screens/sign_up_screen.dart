// import 'package:flutter/material.dart';
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:sport_connect_app/service/auth_service.dart';
// import 'home.dart'; // Make sure this path is correct
// import 'package:sport_connect_app/main.dart'; // Make sure this path is correct

// class SignUpScreen extends StatefulWidget {
//   const SignUpScreen({super.key});

//   @override
//   State<SignUpScreen> createState() => _SignUpScreenState();
// }

// class _SignUpScreenState extends State<SignUpScreen> {
//   final TextEditingController _nameController = TextEditingController();
//   final TextEditingController _emailController = TextEditingController();
//   final TextEditingController _passwordController = TextEditingController();
//   bool _isPasswordVisible = false;
//   bool _agreedToTerms = false;
//   bool _isLoading = false;
//   final AuthService _authService = AuthService();

//   @override
//   void dispose() {
//     _nameController.dispose();
//     _emailController.dispose();
//     _passwordController.dispose();
//     super.dispose();
//   }

//   // Hàm xử lý Đăng ký
//   Future<void> _signUp() async {
//     if (!_agreedToTerms) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Bạn phải đồng ý với Điều khoản và Chính sách.'),
//         ),
//       );
//       return;
//     }

//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final userCredential = await FirebaseAuth.instance
//           .createUserWithEmailAndPassword(
//             email: _emailController.text.trim(),
//             password: _passwordController.text.trim(),
//           );

//       final user = userCredential.user;
//       if (user != null) {
//         // Cập nhật tên hiển thị trong Authentication
//         await user.updateDisplayName(_nameController.text.trim());

//         // MỚI: Gọi hàm để lưu thông tin người dùng vào Firestore
//         // Chúng ta cần tải lại user để lấy displayName vừa cập nhật
//         await user.reload();
//         final updatedUser = FirebaseAuth.instance.currentUser;
//         if (updatedUser != null) {
//           await _authService.saveUserToFirestore(updatedUser);
//         }
//       }

//       if (!mounted) return;

//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Đăng ký thành công!'),
//           backgroundColor: Colors.green,
//         ),
//       );

//       Navigator.of(context).pushAndRemoveUntil(
//         // Sửa thành MainScreen để đồng bộ với SignIn
//         MaterialPageRoute(builder: (context) => const MainScreen()),
//         (route) => false,
//       );
//     } on FirebaseAuthException catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Đăng ký thất bại: ${e.message}'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     }
//   }

//   Future<void> _signUpWithProvider(String provider) async {
//     if (!_agreedToTerms) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         const SnackBar(
//           content: Text('Bạn phải đồng ý với Điều khoản và Chính sách.'),
//         ),
//       );
//       return;
//     }

//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       UserCredential? result;
//       if (provider == 'google') {
//         result = await _authService.signInWithGoogle();
//       } else if (provider == 'facebook') {
//         result = await _authService.signInWithFacebook();
//       }

//       if (result != null) {
//         if (!mounted) return;

//         // Hiển thị thông báo thành công
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Đăng ký thành công!'),
//             backgroundColor: Colors.green,
//           ),
//         );

//         // Chuyển đến màn hình Home và xóa stack điều hướng
//         Navigator.of(context).pushAndRemoveUntil(
//           MaterialPageRoute(builder: (context) => const HomeScreen()),
//           (route) => false,
//         );
//       }
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Đăng ký thất bại: $e'),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       if (mounted) {
//         setState(() {
//           _isLoading = false;
//         });
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     // Lấy kích thước màn hình để căn chỉnh
//     final screenHeight = MediaQuery.of(context).size.height;

//     return Scaffold(
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.symmetric(horizontal: 30.0),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.center,
//             children: <Widget>[
//               SizedBox(height: screenHeight * 0.08),

//               // 1. Tiêu đề và Mô tả
//               const Text(
//                 'Sign Up',
//                 style: TextStyle(
//                   fontSize: 32,
//                   fontWeight: FontWeight.bold,
//                   color: Color(0xFF1976D2),
//                 ),
//               ),
//               const SizedBox(height: 10),
//               const Text(
//                 'Connect your match, match your sport',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(fontSize: 14, color: Colors.grey),
//               ),
//               SizedBox(height: screenHeight * 0.05),

//               // 2. Các nút Đăng nhập Mạng xã hội
//               _buildSocialLoginButtons(context),
//               const SizedBox(height: 30),

//               // 3. Divider "Or"
//               _buildOrDivider(),
//               const SizedBox(height: 30),

//               // 4. Các trường nhập liệu
//               _buildInputField(hintText: 'Name', controller: _nameController),
//               const SizedBox(height: 20),
//               _buildInputField(
//                 hintText: 'Email/Phone Number',
//                 controller: _emailController,
//                 keyboardType: TextInputType.emailAddress,
//               ),
//               const SizedBox(height: 20),
//               _buildPasswordField(
//                 hintText: 'Password',
//                 controller: _passwordController,
//               ),
//               const SizedBox(height: 25),

//               // 5. Checkbox Điều khoản
//               _buildTermsAndPolicyCheckbox(),
//               const SizedBox(height: 30),

//               // 6. Nút "Create Account"
//               _buildCreateAccountButton(context),
//               SizedBox(height: screenHeight * 0.05),

//               // 7. Liên kết "Sign In"
//               _buildSignInLink(),
//               SizedBox(height: screenHeight * 0.02),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // --- WIDGET CON ĐƯỢC CẬP NHẬT ---

//   Widget _buildInputField({
//     required String hintText,
//     required TextEditingController controller,
//     TextInputType keyboardType = TextInputType.text,
//   }) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.grey[100],
//         borderRadius: BorderRadius.circular(10),
//       ),
//       child: TextField(
//         controller: controller,
//         keyboardType: keyboardType,
//         decoration: InputDecoration(
//           hintText: hintText,
//           contentPadding: const EdgeInsets.symmetric(
//             vertical: 18,
//             horizontal: 20,
//           ),
//           border: InputBorder.none,
//         ),
//       ),
//     );
//   }

//   Widget _buildPasswordField({
//     required String hintText,
//     required TextEditingController controller,
//   }) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.grey[100],
//         borderRadius: BorderRadius.circular(10),
//       ),
//       child: TextField(
//         controller: controller,
//         obscureText: !_isPasswordVisible, // Dùng biến trạng thái
//         decoration: InputDecoration(
//           hintText: hintText,
//           contentPadding: const EdgeInsets.symmetric(
//             vertical: 18,
//             horizontal: 20,
//           ),
//           border: InputBorder.none,
//           suffixIcon: IconButton(
//             icon: Icon(
//               _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
//               color: Colors.grey,
//             ),
//             onPressed: () {
//               setState(() {
//                 _isPasswordVisible = !_isPasswordVisible;
//               });
//             },
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildTermsAndPolicyCheckbox() {
//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         SizedBox(
//           width: 24.0,
//           height: 24.0,
//           child: Checkbox(
//             value: _agreedToTerms,
//             onChanged: (bool? newValue) {
//               setState(() {
//                 _agreedToTerms = newValue ?? false;
//               });
//             },
//             activeColor: const Color(0xFF1976D2),
//           ),
//         ),
//         const SizedBox(width: 8),
//         Expanded(
//           child: RichText(
//             text: const TextSpan(
//               text: "I'm agree to The ",
//               style: TextStyle(color: Colors.black, fontSize: 13),
//               children: <TextSpan>[
//                 TextSpan(
//                   text: 'Terms of Service',
//                   style: TextStyle(
//                     color: Color(0xFF1976D2),
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//                 TextSpan(text: ' and '),
//                 TextSpan(
//                   text: 'Privacy Policy',
//                   style: TextStyle(
//                     color: Color(0xFF1976D2),
//                     fontWeight: FontWeight.bold,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildCreateAccountButton(BuildContext context) {
//     return SizedBox(
//       width: double.infinity,
//       height: 55,
//       child: ElevatedButton(
//         onPressed: _isLoading ? null : _signUp, // Vô hiệu hóa khi đang tải
//         style: ElevatedButton.styleFrom(
//           backgroundColor: const Color(0xFF3F51B5),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(10),
//           ),
//           elevation: 5,
//         ),
//         child: _isLoading
//             ? const CircularProgressIndicator(color: Colors.white)
//             : const Text(
//                 'Creat Account',
//                 style: TextStyle(
//                   fontSize: 18,
//                   color: Colors.white,
//                   fontWeight: FontWeight.bold,
//                 ),
//               ),
//       ),
//     );
//   }

//   Widget _buildSignInLink() {
//     return Row(
//       mainAxisAlignment: MainAxisAlignment.center,
//       children: <Widget>[
//         const Text(
//           'Do you have account? ',
//           style: TextStyle(fontSize: 15, color: Colors.black87),
//         ),
//         InkWell(
//           onTap: () {
//             // Dùng Navigator.pop để quay lại màn hình Sign In (nếu được push từ Sign In)
//             // Nếu không, dùng pushReplacement để thay thế màn hình hiện tại
//             Navigator.of(context).pop();
//           },
//           child: const Text(
//             'Sign In',
//             style: TextStyle(
//               fontSize: 15,
//               color: Color(0xFF3F51B5),
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ),
//       ],
//     );
//   }

//   // Giữ nguyên các Widget không thay đổi (_SocialButton, _buildSocialLoginButtons, _buildOrDivider)
//   Widget _buildSocialLoginButtons(BuildContext context) {
//     return Row(
//       children: <Widget>[
//         Expanded(
//           child: _SocialButton(
//             label: 'Facebook',
//             icon: Icons.facebook,
//             color: Colors.blue[700]!,
//             onPressed: _isLoading
//                 ? null
//                 : () {
//                     _signUpWithProvider('facebook');
//                   },
//           ),
//         ),
//         const SizedBox(width: 15),
//         Expanded(
//           child: _SocialButton(
//             label: 'Google',
//             icon: Icons.g_mobiledata,
//             color: Colors.red[600]!,
//             isGoogle: true,
//             onPressed: _isLoading
//                 ? null
//                 : () {
//                     _signUpWithProvider('google');
//                   },
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildOrDivider() {
//     return Row(
//       children: [
//         const Expanded(child: Divider(color: Colors.grey, thickness: 1)),
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 10.0),
//           child: Text(
//             'Or',
//             style: TextStyle(
//               color: Colors.grey[600],
//               fontWeight: FontWeight.bold,
//             ),
//           ),
//         ),
//         const Expanded(child: Divider(color: Colors.grey, thickness: 1)),
//       ],
//     );
//   }
// }

// // Giữ nguyên _SocialButton
// class _SocialButton extends StatelessWidget {
//   final String label;
//   final IconData icon;
//   final Color color;
//   final bool isGoogle;
//   final VoidCallback? onPressed;

//   const _SocialButton({
//     required this.label,
//     required this.icon,
//     required this.color,
//     this.isGoogle = false,
//     this.onPressed,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       height: 50,
//       decoration: BoxDecoration(
//         color: Colors.white,
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: Colors.grey.shade300, width: 1.5),
//       ),
//       child: TextButton(
//         onPressed: onPressed,
//         child: Row(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: <Widget>[
//             isGoogle
//                 ? const Text(
//                     'G',
//                     style: TextStyle(
//                       color: Colors.red,
//                       fontSize: 22,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   )
//                 : Icon(icon, color: color, size: 24),
//             const SizedBox(width: 10),
//             Text(
//               label,
//               style: TextStyle(color: Colors.grey[700], fontSize: 16),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// THÊM MỚI: Import Firestore
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sport_connect_app/service/auth_service.dart';
import 'home.dart'; // Make sure this path is correct
import 'package:sport_connect_app/main.dart'; // Make sure this path is correct

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _agreedToTerms = false;
  bool _isLoading = false;
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // SỬA ĐỔI: Hàm xử lý Đăng ký
  Future<void> _signUp() async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn phải đồng ý với Điều khoản và Chính sách.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      final user = userCredential.user;
      if (user != null) {
        // Cập nhật tên hiển thị trong Authentication
        await user.updateDisplayName(_nameController.text.trim());

        // Tải lại user để lấy displayName vừa cập nhật
        await user.reload();
        final updatedUser = FirebaseAuth.instance.currentUser;

        // === SỬA ĐỔI: Thay thế _authService.saveUserToFirestore ===
        if (updatedUser != null) {
          // Ghi trực tiếp vào Firestore với 3 trường mới
          await FirebaseFirestore.instance
              .collection('users')
              .doc(updatedUser.uid)
              .set({
                'displayName': updatedUser.displayName,
                'email': updatedUser.email,
                'photoURL': updatedUser.photoURL,
                'createdAt': FieldValue.serverTimestamp(), // (Good practice)
                // CÁC TRƯỜNG BẠN YÊU CẦU:
                'friends': [],
                'friendRequestsSent': [],
                'friendRequestsReceived': [],
              }, SetOptions(merge: true)); // Dùng merge để an toàn
        }
        // =========================================================
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đăng ký thành công!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pushAndRemoveUntil(
        // Sửa thành MainScreen để đồng bộ với SignIn
        MaterialPageRoute(builder: (context) => const MainScreen()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đăng ký thất bại: ${e.message}'),
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

  Future<void> _signUpWithProvider(String provider) async {
    if (!_agreedToTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn phải đồng ý với Điều khoản và Chính sách.'),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      UserCredential? result;
      if (provider == 'google') {
        result = await _authService.signInWithGoogle();
      } else if (provider == 'facebook') {
        result = await _authService.signInWithFacebook();
      }

      // ⚠️ LƯU Ý: Chỗ này đang dựa vào _authService
      // Bạn cần đảm bảo hàm signInWithGoogle/signInWithFacebook
      // bên trong AuthService cũng thêm 3 trường rỗng kia!

      if (result != null) {
        if (!mounted) return;

        // Hiển thị thông báo thành công
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đăng ký thành công!'),
            backgroundColor: Colors.green,
          ),
        );

        // Chuyển đến màn hình Home và xóa stack điều hướng
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đăng ký thất bại: $e'),
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
    // Lấy kích thước màn hình để căn chỉnh
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 30.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(height: screenHeight * 0.08),

              // 1. Tiêu đề và Mô tả
              const Text(
                'Sign Up',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Connect your match, match your sport',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              SizedBox(height: screenHeight * 0.05),

              // 2. Các nút Đăng nhập Mạng xã hội
              _buildSocialLoginButtons(context),
              const SizedBox(height: 30),

              // 3. Divider "Or"
              _buildOrDivider(),
              const SizedBox(height: 30),

              // 4. Các trường nhập liệu
              _buildInputField(hintText: 'Name', controller: _nameController),
              const SizedBox(height: 20),
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
              const SizedBox(height: 25),

              // 5. Checkbox Điều khoản
              _buildTermsAndPolicyCheckbox(),
              const SizedBox(height: 30),

              // 6. Nút "Create Account"
              _buildCreateAccountButton(context),
              SizedBox(height: screenHeight * 0.05),

              // 7. Liên kết "Sign In"
              _buildSignInLink(),
              SizedBox(height: screenHeight * 0.02),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET CON ĐƯỢC CẬP NHẬT ---

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
      child: TextField(
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
        obscureText: !_isPasswordVisible, // Dùng biến trạng thái
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

  Widget _buildTermsAndPolicyCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24.0,
          height: 24.0,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (bool? newValue) {
              setState(() {
                _agreedToTerms = newValue ?? false;
              });
            },
            activeColor: const Color(0xFF1976D2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: const TextSpan(
              text: "I'm agree to The ",
              style: TextStyle(color: Colors.black, fontSize: 13),
              children: <TextSpan>[
                TextSpan(
                  text: 'Terms of Service',
                  style: TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextSpan(text: ' and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: TextStyle(
                    color: Color(0xFF1976D2),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateAccountButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _signUp, // Vô hiệu hóa khi đang tải
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
                'Creat Account',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildSignInLink() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Text(
          'Do you have account? ',
          style: TextStyle(fontSize: 15, color: Colors.black87),
        ),
        InkWell(
          onTap: () {
            // Dùng Navigator.pop để quay lại màn hình Sign In (nếu được push từ Sign In)
            // Nếu không, dùng pushReplacement để thay thế màn hình hiện tại
            Navigator.of(context).pop();
          },
          child: const Text(
            'Sign In',
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

  // Giữ nguyên các Widget không thay đổi (_SocialButton, _buildSocialLoginButtons, _buildOrDivider)
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
                : () {
                    _signUpWithProvider('facebook');
                  },
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
                : () {
                    _signUpWithProvider('google');
                  },
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
}

// Giữ nguyên _SocialButton
class _SocialButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool isGoogle;
  final VoidCallback? onPressed;

  const _SocialButton({
    required this.label,
    required this.icon,
    required this.color,
    this.isGoogle = false,
    this.onPressed,
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
        onPressed: onPressed,
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
