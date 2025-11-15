import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);

  // MỚI: Hàm lưu thông tin người dùng vào Firestore
  Future<void> saveUserToFirestore(User user) async {
    try {
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      final doc = await userRef.get();

      // Chỉ tạo mới document nếu nó chưa tồn tại
      if (!doc.exists) {
        await userRef.set({
          'uid': user.uid,
          'displayName':
              user.displayName ?? user.email?.split('@')[0] ?? 'New User',
          'email': user.email,
          'photoURL': user.photoURL ?? '',
        });
        print('User data saved to Firestore for ${user.uid}');
      }
    } catch (e) {
      print('Error saving user to Firestore: $e');
      // Không ném lỗi ra ngoài để không làm gián đoạn luồng đăng nhập
    }
  }

  // CẬP NHẬT: Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // MỚI: Lưu thông tin người dùng sau khi đăng nhập thành công
      if (userCredential.user != null) {
        await saveUserToFirestore(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      print("Lỗi khi đăng nhập bằng Google: $e");
      return null;
    }
  }

  // CẬP NHẬT: Sign in with Facebook
  Future<UserCredential?> signInWithFacebook() async {
    try {
      final LoginResult result = await FacebookAuth.instance.login();

      if (result.status == LoginStatus.success) {
        final AccessToken accessToken = result.accessToken!;
        final OAuthCredential credential = FacebookAuthProvider.credential(
          accessToken.tokenString,
        );
        final userCredential = await _auth.signInWithCredential(credential);

        // MỚI: Lưu thông tin người dùng sau khi đăng nhập thành công
        if (userCredential.user != null) {
          await saveUserToFirestore(userCredential.user!);
        }

        return userCredential;
      } else {
        print(
          'Đăng nhập Facebook không thành công: ${result.status} - ${result.message}',
        );
        return null;
      }
    } catch (e) {
      print("Lỗi khi đăng nhập bằng Facebook: $e");
      return null;
    }
  }

  /// Cho phép người dùng chọn ảnh, tải lên Storage và cập nhật hồ sơ.
  Future<void> uploadAvatarAndUpdateProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception("User is not logged in.");
    }

    // 1. Dùng image_picker để người dùng chọn ảnh
    final picker = ImagePicker();
    final XFile? pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
    );

    if (pickedFile == null) {
      return; // Người dùng đã hủy chọn ảnh
    }

    File imageFile = File(pickedFile.path);

    try {
      // 2. Tải file ảnh lên Cloud Storage
      // Tạo một tham chiếu đến vị trí bạn muốn lưu file, ví dụ: 'avatars/user_uid.jpg'
      final storageRef = FirebaseStorage.instance.ref().child(
        'avatars/${user.uid}',
      );
      final uploadTask = storageRef.putFile(imageFile);

      // Chờ cho đến khi quá trình tải lên hoàn tất
      final snapshot = await uploadTask.whenComplete(() => {});

      // 3. Lấy Download URL công khai của ảnh
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      // 4. Cập nhật URL này vào Firestore và Authentication
      // Cập nhật vào Firestore collection 'users'
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update(
        {'photoURL': downloadUrl},
      );

      // Cập nhật vào hồ sơ Authentication (để đồng bộ)
      await user.updatePhotoURL(downloadUrl);

      print('Avatar updated successfully!');
    } on FirebaseException catch (e) {
      print('Error uploading avatar: $e');
      throw Exception('Failed to update avatar.');
    }
  }
}
