import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'settings_screen.dart';
import 'notice_screen.dart'; // Import màn hình thông báo
import '../widgets/recommended_fields_section.dart';
import '../widgets/sports_news_section.dart';

// THÊM MỚI: Import màn hình hồ sơ người dùng
import 'user_profile_screen.dart';

// THÊM MỚI: Một class nhỏ để chứa dữ liệu kết quả tìm kiếm
class UserSearchResult {
  final String uid;
  final String displayName;
  final String email;
  final String? photoURL;

  UserSearchResult({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoURL,
  });

  // Factory constructor để tạo từ một Firestore doc
  factory UserSearchResult.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserSearchResult(
      uid: doc.id,
      displayName: data['displayName'] ?? 'Không có tên',
      email: data['email'] ?? 'Không có email',
      photoURL: data['photoURL'],
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin<HomeScreen> {
  @override
  bool get wantKeepAlive => true;

  // Key để RefreshIndicator
  final GlobalKey<SportsNewsSectionState> _sportsKey = GlobalKey();
  final GlobalKey<RecommendedFieldsSectionState> _recommendedKey = GlobalKey();

  // SỬA ĐỔI: Chúng ta không cần _searchController và _isSearching nữa
  // vì Autocomplete sẽ quản lý chúng.

  @override
  void dispose() {
    // Không cần dispose _searchController nữa
    super.dispose();
  }

  Future<void> _refreshData() async {
    await Future.wait([
      _sportsKey.currentState?.refreshNews() ?? Future.value(),
      _recommendedKey.currentState?.refreshFields() ?? Future.value(),
    ]);
  }

  // SỬA ĐỔI: Hàm _handleSearch bị XÓA và thay bằng hàm mới

  // THÊM MỚI: Hàm tìm kiếm "as-you-type"
  Future<Iterable<UserSearchResult>> _searchUsers(String query) async {
    if (query.isEmpty) {
      return []; // Không tìm kiếm nếu chuỗi rỗng
    }

    final lowerQuery = query.toLowerCase();

    try {
      // SỬA ĐỔI: Tìm theo 'email' vì nó thường là lowercase
      // Logic "starts-with": >= query VÀ < query + ký tự \uf8ff
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isGreaterThanOrEqualTo: lowerQuery)
          .where('email', isLessThan: lowerQuery + '\uf8ff')
          .limit(5) // Luôn giới hạn kết quả live search
          .get();

      // Trả về một danh sách (Iterable) các UserSearchResult
      return snapshot.docs.map((doc) => UserSearchResult.fromDoc(doc));
    } catch (e) {
      print("Lỗi khi tìm kiếm: $e");
      // Bạn sẽ thấy lỗi về Index ở đây. Hãy click vào link
      // để tạo Index trong Firebase Console.
      return []; // Trả về rỗng nếu có lỗi
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        // SỬA ĐỔI: Bọc body bằng GestureDetector để ẩn bàn phím khi
        // người dùng nhấn ra ngoài
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refreshData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 18),
                        _buildWelcomeSection(context),
                        const SizedBox(height: 18),
                        SportsNewsSection(key: _sportsKey),
                        const SizedBox(height: 18),
                        RecommendedFieldsSection(key: _recommendedKey),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // WIDGET ICON THÔNG BÁO ĐỘNG (giữ nguyên)
  Widget _buildNotificationIcon(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return IconButton(
        icon: Icon(Icons.notifications_none, color: Colors.grey[700], size: 26),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => const NoticeScreen())),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('joinRequests')
          .where('ownerId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final hasNotifications =
            snapshot.hasData && snapshot.data!.docs.isNotEmpty;

        return InkWell(
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => const NoticeScreen())),
          borderRadius: BorderRadius.circular(50),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none,
                  color: Colors.grey[700],
                  size: 26,
                ),
                if (hasNotifications)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // HEADER (giữ nguyên)
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'SportConnect',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color.fromRGBO(7, 7, 112, 1),
            ),
          ),
          Row(
            children: [
              _buildNotificationIcon(context),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                ),
                borderRadius: BorderRadius.circular(50),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.settings_outlined,
                    color: Colors.grey[700],
                    size: 26,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // WELCOME SECTION (giữ nguyên)
  Widget _buildWelcomeSection(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final username = user?.displayName ?? user?.email ?? 'User';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thanh tìm kiếm đã được cập nhật
          _buildSearchBar(),
          const SizedBox(height: 18),
          Text(
            'Welcome to SportConnect, $username',
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            "Let's get connect with your teammates and be ready for the game.",
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  // SỬA ĐỔI: Thanh tìm kiếm đã được CẤU TRÚC LẠI HOÀN TOÀN
  Widget _buildSearchBar() {
    return Autocomplete<UserSearchResult>(
      // 1. Hàm cung cấp gợi ý (gọi hàm search của chúng ta)
      optionsBuilder: (TextEditingValue textEditingValue) {
        return _searchUsers(textEditingValue.text);
      },

      // 2. Tùy chỉnh giao diện danh sách gợi ý
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          // Dùng Material để có bóng đổ và nền trắng
          child: Material(
            elevation: 4.0,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              // Giới hạn chiều rộng bằng chiều rộng màn hình trừ đi padding
              width: MediaQuery.of(context).size.width - (18 * 2),
              // Giới hạn chiều cao
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final user = options.elementAt(index);
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundImage: (user.photoURL != null)
                          ? NetworkImage(user.photoURL!)
                          : null,
                      child: (user.photoURL == null)
                          ? const Icon(Icons.person, size: 20)
                          : null,
                    ),
                    title: Text(user.displayName),
                    subtitle: Text(user.email),
                    onTap: () {
                      onSelected(user); // Gọi hàm onSelected khi nhấn vào
                    },
                  );
                },
              ),
            ),
          ),
        );
      },

      // 3. Hàm được gọi khi 1 gợi ý được chọn
      onSelected: (UserSearchResult selection) {
        FocusScope.of(context).unfocus(); // Ẩn bàn phím
        _searchController.clear(); // Xóa chữ trong thanh tìm kiếm
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: selection.uid),
          ),
        );
      },

      // 4. Hiển thị gì trong TextField (ở đây là không hiển thị gì,
      // vì chúng ta điều hướng luôn)
      displayStringForOption: (UserSearchResult option) => '',

      // 5. Tùy chỉnh TextField (fieldViewBuilder)
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            // Gán controller bên ngoài để có thể xóa text
            _searchController = textEditingController;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: Colors.grey[500], size: 22),
                  Expanded(
                    child: TextField(
                      controller: textEditingController,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        hintText: 'Tìm người dùng bằng Email', // Sửa gợi ý
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 10,
                        ),
                      ),
                    ),
                  ),
                  //Icon(Icons.mic_none, color: Colors.grey[500], size: 22),
                ],
              ),
            );
          },
    );
  }

  // Thêm một controller toàn cục cho _HomeScreenState
  // để có thể xóa text sau khi chọn
  late TextEditingController _searchController;
}
