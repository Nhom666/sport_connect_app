import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'edit_profile_screen.dart';
import 'personal_chat_screen.dart'; // <-- Import file chat cá nhân

// Enum để quản lý trạng thái quan hệ
enum FriendshipStatus {
  Loading,
  Me,
  None,
  RequestSent,
  RequestReceived,
  Friends,
}

// Chuyển thành StatefulWidget
class UserProfileScreen extends StatefulWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  // Các biến trạng thái
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  DocumentSnapshot? _profileUserDoc;
  DocumentSnapshot? _currentUserDoc;
  FriendshipStatus _status = FriendshipStatus.Loading;
  bool _isProcessing = false; // Trạng thái khi nhấn nút

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Hàm tải dữ liệu của cả 2 user để xác định mối quan hệ
  Future<void> _loadUserData() async {
    if (currentUserId == null) return;

    // 1. Kiểm tra nếu là chính mình
    if (currentUserId == widget.userId) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      if (mounted) {
        setState(() {
          _profileUserDoc = doc;
          _status = FriendshipStatus.Me;
        });
      }
      return;
    }

    // 2. Tải đồng thời profile của 2 user
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(widget.userId).get(),
        FirebaseFirestore.instance.collection('users').doc(currentUserId).get(),
      ]);

      if (!mounted) return;

      final profileDoc = results[0];
      final currentUserDoc = results[1];

      // 3. Xác định mối quan hệ
      final currentUserData = currentUserDoc.data() as Map<String, dynamic>;

      final friends = List<String>.from(currentUserData['friends'] ?? []);
      final sentRequests = List<String>.from(
        currentUserData['friendRequestsSent'] ?? [],
      );
      final receivedRequests = List<String>.from(
        currentUserData['friendRequestsReceived'] ?? [],
      );

      FriendshipStatus newStatus;
      if (friends.contains(widget.userId)) {
        newStatus = FriendshipStatus.Friends;
      } else if (sentRequests.contains(widget.userId)) {
        newStatus = FriendshipStatus.RequestSent;
      } else if (receivedRequests.contains(widget.userId)) {
        newStatus = FriendshipStatus.RequestReceived;
      } else {
        newStatus = FriendshipStatus.None;
      }

      setState(() {
        _profileUserDoc = profileDoc;
        _currentUserDoc = currentUserDoc;
        _status = newStatus;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: ${e.toString()}')),
        );
      }
    }
  } // <-- HÀM _loadUserData KẾT THÚC TẠI ĐÂY

  // --- UPDATED: Hàm này phải được đặt ở đây, bên ngoài _loadUserData ---
  void _navigateToChatScreen() {
    if (_profileUserDoc == null) return;

    final userData = _profileUserDoc!.data() as Map<String, dynamic>;
    final friendId = widget.userId;
    final friendName = userData['displayName'] ?? 'Không có tên';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            PersonalChatScreen(friendId: friendId, friendName: friendName),
      ),
    );
  }
  // ---------------------------------------------------------------

  // === CÁC HÀM XỬ LÝ LOGIC BẠN BÈ ===
  // (Giữ nguyên các hàm: _sendFriendRequest, _cancelOrRejectFriendRequest,
  // _acceptFriendRequest, _unfriendUser, _showTeamInviteDialog)

  // 1. Gửi yêu cầu
  Future<void> _sendFriendRequest() async {
    if (_currentUserDoc == null ||
        _profileUserDoc == null ||
        currentUserId == null)
      return;
    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Thêm ID người nhận vào mảng 'sent' của mình
      batch.update(_currentUserDoc!.reference, {
        'friendRequestsSent': FieldValue.arrayUnion([widget.userId]),
      });
      // Thêm ID của mình vào mảng 'received' của người nhận
      batch.update(_profileUserDoc!.reference, {
        'friendRequestsReceived': FieldValue.arrayUnion([currentUserId]),
      });

      await batch.commit();
      if (mounted) {
        setState(() {
          _status = FriendshipStatus.RequestSent;
          _isProcessing = false;
        });
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Đã gửi yêu cầu kết bạn.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Gửi yêu cầu thất bại: ${e.toString()}')),
        );
      }
    }
  }

  // 2. Hủy yêu cầu (khi mình đã gửi) HOẶC Từ chối (khi mình nhận được)
  Future<void> _cancelOrRejectFriendRequest(String snackbarMessage) async {
    if (_currentUserDoc == null ||
        _profileUserDoc == null ||
        currentUserId == null)
      return;
    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Xóa ID người nhận khỏi mảng 'sent' của mình
      batch.update(_currentUserDoc!.reference, {
        'friendRequestsSent': FieldValue.arrayRemove([widget.userId]),
        'friendRequestsReceived': FieldValue.arrayRemove([
          widget.userId,
        ]), // Dùng cho case "Từ chối"
      });
      // Xóa ID của mình khỏi mảng 'received' của người nhận
      batch.update(_profileUserDoc!.reference, {
        'friendRequestsReceived': FieldValue.arrayRemove([currentUserId]),
        'friendRequestsSent': FieldValue.arrayRemove([
          currentUserId,
        ]), // Dùng cho case "Từ chối"
      });

      await batch.commit();
      if (mounted) {
        setState(() {
          _status = FriendshipStatus.None;
          _isProcessing = false;
        });
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(snackbarMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Lỗi: ${e.toString()}')),
        );
      }
    }
  }

  // 3. Chấp nhận yêu cầu (khi mình nhận được)
  Future<void> _acceptFriendRequest() async {
    if (_currentUserDoc == null ||
        _profileUserDoc == null ||
        currentUserId == null)
      return;
    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Cập nhật doc của mình: xóa khỏi 'received', thêm vào 'friends'
      batch.update(_currentUserDoc!.reference, {
        'friendRequestsReceived': FieldValue.arrayRemove([widget.userId]),
        'friends': FieldValue.arrayUnion([widget.userId]),
      });
      // Cập nhật doc của họ: xóa khỏi 'sent', thêm vào 'friends'
      batch.update(_profileUserDoc!.reference, {
        'friendRequestsSent': FieldValue.arrayRemove([currentUserId]),
        'friends': FieldValue.arrayUnion([currentUserId]),
      });

      await batch.commit();
      if (mounted) {
        setState(() {
          _status = FriendshipStatus.Friends;
          _isProcessing = false;
        });
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Đã chấp nhận kết bạn.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Lỗi: ${e.toString()}')),
        );
      }
    }
  }

  // 4. Hủy kết bạn (khi đã là bạn)
  Future<void> _unfriendUser() async {
    if (_currentUserDoc == null ||
        _profileUserDoc == null ||
        currentUserId == null)
      return;
    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final batch = FirebaseFirestore.instance.batch();

      // Xóa ID người kia khỏi mảng 'friends' của mình
      batch.update(_currentUserDoc!.reference, {
        'friends': FieldValue.arrayRemove([widget.userId]),
      });
      // Xóa ID của mình khỏi mảng 'friends' của người kia
      batch.update(_profileUserDoc!.reference, {
        'friends': FieldValue.arrayRemove([currentUserId]),
      });

      await batch.commit();
      if (mounted) {
        setState(() {
          _status = FriendshipStatus.None;
          _isProcessing = false;
        });
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Đã hủy kết bạn.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Lỗi: ${e.toString()}')),
        );
      }
    }
  }

  // === HÀM XỬ LÝ MỜI VÀO ĐỘI ===
  Future<void> _showTeamInviteDialog() async {
    if (currentUserId == null) return;
    setState(() => _isProcessing = true);

    final teamsSnapshot = await FirebaseFirestore.instance
        .collection('teams')
        .where('ownerId', isEqualTo: currentUserId)
        .get();
    final List<QueryDocumentSnapshot> ownedTeams = teamsSnapshot.docs;

    if (mounted) setState(() => _isProcessing = false);

    if (ownedTeams.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bạn chưa tạo đội nào. Hãy tạo đội và quay lại sau.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (mounted) {
      showModalBottomSheet(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (BuildContext context, StateSetter setSheetState) {
              bool isSheetLoading = false;
              String? invitingTeamId;

              Future<void> sendInvitation(
                String teamId,
                String teamName,
                List<String> members,
                int maxMembers,
              ) async {
                setSheetState(() {
                  isSheetLoading = true;
                  invitingTeamId = teamId;
                });

                if (members.contains(widget.userId)) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Người này đã ở trong đội của bạn.'),
                    ),
                  );
                  Navigator.of(ctx).pop();
                  return;
                }

                if (members.length >= maxMembers) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Thành viên của team đã đủ.')),
                  );
                  setSheetState(() => isSheetLoading = false);
                  return;
                }

                final invitationQuery = await FirebaseFirestore.instance
                    .collection('teamInvitations')
                    .where('teamId', isEqualTo: teamId)
                    .where('inviteeId', isEqualTo: widget.userId)
                    .where('status', isEqualTo: 'pending')
                    .limit(1)
                    .get();

                if (invitationQuery.docs.isNotEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Bạn đã mời người này vào đội rồi.'),
                    ),
                  );
                  Navigator.of(ctx).pop();
                  return;
                }

                try {
                  await FirebaseFirestore.instance
                      .collection('teamInvitations')
                      .add({
                        'inviterId': currentUserId,
                        'inviterName':
                            _currentUserDoc?.get('displayName') ?? 'Chủ đội',
                        'inviteeId': widget.userId,
                        'teamId': teamId,
                        'teamName': teamName,
                        'status': 'pending',
                        'createdAt': FieldValue.serverTimestamp(),
                      });

                  if (mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('Đã gửi lời mời.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    Navigator.of(ctx).pop();
                  }
                } catch (e) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('Lỗi: ${e.toString()}')),
                  );
                } finally {
                  if (mounted) {
                    setSheetState(() => isSheetLoading = false);
                  }
                }
              }

              return Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Mời vào đội',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: ownedTeams.length,
                        itemBuilder: (context, index) {
                          final teamDoc = ownedTeams[index];
                          final teamData =
                              teamDoc.data() as Map<String, dynamic>;
                          final teamId = teamDoc.id;
                          final teamName =
                              teamData['teamName'] ?? 'Unnamed Team';
                          final List<String> members = List<String>.from(
                            teamData['members'] ?? [],
                          );
                          final int maxMembers =
                              (teamData['memberCount'] as num?)?.toInt() ?? 5;

                          final bool isAlreadyMember = members.contains(
                            widget.userId,
                          );
                          final bool isFull = members.length >= maxMembers;
                          String buttonText = "Mời";
                          bool disabled = false;

                          if (isAlreadyMember) {
                            buttonText = "Đã Tham gia";
                            disabled = true;
                          } else if (isFull) {
                            buttonText = "Đầy";
                            disabled = true;
                          }

                          return Card(
                            child: ListTile(
                              title: Text(teamName),
                              subtitle: Text(
                                "${members.length}/$maxMembers thành viên",
                              ),
                              trailing:
                                  (isSheetLoading && invitingTeamId == teamId)
                                  ? const CircularProgressIndicator()
                                  : ElevatedButton(
                                      onPressed: disabled || isSheetLoading
                                          ? null
                                          : () => sendInvitation(
                                              teamId,
                                              teamName,
                                              members,
                                              maxMembers,
                                            ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: disabled
                                            ? Colors.grey
                                            : Colors.blue,
                                      ),
                                      child: Text(buttonText),
                                    ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status == FriendshipStatus.Loading || _profileUserDoc == null) {
      return Scaffold(
        backgroundColor: Colors.grey[100],
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    // SỬA ĐỔI: Lấy thêm dữ liệu từ doc
    final userData = _profileUserDoc!.data() as Map<String, dynamic>;
    final displayName = userData['displayName'] ?? 'Không có tên';
    final email = userData['email'] ?? 'Không có email';
    final photoUrl = userData['photoURL'];
    // THÊM MỚI: Lấy dữ liệu profile
    final String? favoriteSport = userData['favoriteSport'];
    final String? level = userData['level'];
    final List<String> freeSchedules = List<String>.from(
      userData['freeSchedules'] ?? [],
    );

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Stack(
        children: [
          Container(
            height: 200,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue, Color.fromARGB(255, 3, 96, 210)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 60,
                      backgroundImage: photoUrl != null
                          ? NetworkImage(photoUrl)
                          : null,
                      backgroundColor: Colors.grey[200],
                      child: photoUrl == null
                          ? Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.grey[600],
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  email,
                  style: TextStyle(fontSize: 16, color: Colors.grey[700]),
                ),
                const SizedBox(height: 24),

                // === THÊM MỚI: CARD THÔNG TIN PROFILE ===
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildProfileDetailTile(
                            icon: Icons.sports_soccer,
                            label: 'Môn thể thao yêu thích',
                            value: favoriteSport,
                            iconColor: Colors.green,
                          ),
                          const Divider(height: 20, thickness: 0.5),
                          _buildProfileDetailTile(
                            icon: Icons.star_border,
                            label: 'Trình độ',
                            value: level,
                            iconColor: Colors.orange,
                          ),
                          const Divider(height: 20, thickness: 0.5),
                          // Widget riêng cho Lịch rảnh (vì nó là 1 list)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.schedule,
                                color: Colors.purple,
                                size: 22,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Lịch trình rảnh rỗi',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (freeSchedules.isEmpty)
                                      const Text(
                                        '-',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black87,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      )
                                    else
                                      Wrap(
                                        spacing: 6.0,
                                        runSpacing: 4.0,
                                        children: freeSchedules
                                            .map(
                                              (schedule) => Chip(
                                                label: Text(schedule),
                                                backgroundColor:
                                                    Colors.purple.shade50,
                                                labelStyle: TextStyle(
                                                  color: Colors.purple.shade900,
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 12,
                                                ),
                                                side: BorderSide.none,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 0,
                                                    ),
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                              ),
                                            )
                                            .toList(),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ======================================
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: _buildActionButtons(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'UID: ${widget.userId}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  // --- UPDATED: Thêm nút "Nhắn tin" ---
  Widget _buildActionButtons() {
    if (_isProcessing) {
      return const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(),
        ),
      );
    }

    List<Widget> actionWidgets = [];

    switch (_status) {
      case FriendshipStatus.Me:
        actionWidgets.add(
          _buildActionButton(
            context: context,
            icon: Icons.edit,
            label: 'Chỉnh sửa hồ sơ',
            color: Colors.orange,
            onPressed: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (context) => const EditProfileScreen(),
                    ),
                  )
                  .then((_) => _loadUserData()); // Tải lại data khi quay về
            },
          ),
        );
        break;
      case FriendshipStatus.None:
        actionWidgets.add(
          _buildActionButton(
            context: context,
            icon: Icons.person_add_alt_1,
            label: 'Gửi yêu cầu kết bạn',
            color: Colors.blue,
            onPressed: _sendFriendRequest,
          ),
        );
        break;
      case FriendshipStatus.RequestSent:
        actionWidgets.add(
          _buildActionButton(
            context: context,
            icon: Icons.cancel_schedule_send,
            label: 'Hủy yêu cầu kết bạn',
            color: Colors.grey,
            onPressed: () =>
                _cancelOrRejectFriendRequest('Đã hủy yêu cầu kết bạn.'),
          ),
        );
        break;
      case FriendshipStatus.RequestReceived:
        actionWidgets.add(
          _buildActionButton(
            context: context,
            icon: Icons.check_circle,
            label: 'Chấp nhận yêu cầu',
            color: Colors.green,
            onPressed: _acceptFriendRequest,
          ),
        );
        actionWidgets.add(const Divider(height: 20));
        actionWidgets.add(
          _buildActionButton(
            context: context,
            icon: Icons.cancel,
            label: 'Từ chối yêu cầu',
            color: Colors.red,
            onPressed: () =>
                _cancelOrRejectFriendRequest('Đã từ chối yêu cầu.'),
          ),
        );
        break;
      case FriendshipStatus.Friends:
        // --- (BẮT ĐẦU THAY ĐỔI) ---
        // 1. Thêm nút "Nhắn tin"
        actionWidgets.add(
          _buildActionButton(
            context: context,
            icon: Icons.chat, // <-- Icon mới
            label: 'Nhắn tin', // <-- Label mới
            color: Colors.blue, // <-- Màu mới
            onPressed: _navigateToChatScreen, // <-- Hàm đã di chuyển
          ),
        );
        actionWidgets.add(const Divider(height: 20)); // Thêm ngăn cách
        // 2. Giữ lại nút "Hủy kết bạn"
        actionWidgets.add(
          _buildActionButton(
            context: context,
            icon: Icons.person_remove,
            label: 'Hủy kết bạn',
            color: Colors.red,
            onPressed: _unfriendUser,
          ),
        );
        // --- (KẾT THÚC THAY ĐỔI) ---
        break;
      default: // Gồm cả Loading
        break;
    }

    // Thêm nút "Mời vào đội" nếu không phải là chính mình
    if (_status != FriendshipStatus.Me && _status != FriendshipStatus.Loading) {
      if (actionWidgets.isNotEmpty) {
        actionWidgets.add(const Divider(height: 20));
      }
      actionWidgets.add(
        _buildActionButton(
          context: context,
          icon: Icons.group_add,
          label: 'Mời vào đội',
          color: Colors.green,
          onPressed: _showTeamInviteDialog,
        ),
      );
    }

    return Column(children: actionWidgets);
  }

  // Helper widget để tạo các nút hành động (Không đổi)
  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 16),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.black87,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  // --- THÊM MỚI: HELPER WIDGET CHO THÔNG TIN PROFILE ---
  Widget _buildProfileDetailTile({
    required IconData icon,
    required String label,
    required String? value,
    required Color iconColor,
  }) {
    // Hiển thị '-' nếu giá trị là null hoặc rỗng
    final displayValue = (value == null || value.isEmpty) ? '-' : value;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                displayValue,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
