import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key});

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  bool _isProcessing = false;

  // --- HÀM XỬ LÝ TEAM REQUEST (Xin vào đội) ---
  void _acceptRequest(
    String requestId,
    String teamId,
    String requesterId,
  ) async {
    // TODO: Thêm logic kiểm tra team có bị đầy không trước khi accept
    if (!mounted) return;
    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      final batch = FirebaseFirestore.instance.batch();

      final teamRef = FirebaseFirestore.instance
          .collection('teams')
          .doc(teamId);
      batch.update(teamRef, {
        'members': FieldValue.arrayUnion([requesterId]),
      });

      final requestRef = FirebaseFirestore.instance
          .collection('joinRequests')
          .doc(requestId);
      batch.update(requestRef, {'status': 'accepted'});

      await batch.commit();
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Member accepted.')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to accept request: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _rejectRequest(String requestId) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('joinRequests')
          .doc(requestId)
          .update({'status': 'rejected'});

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Member rejected.')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to reject request: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- HÀM XỬ LÝ FRIEND REQUEST (Kết bạn) ---
  Future<void> _acceptFriendRequest(String requesterId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || !mounted) return;
    setState(() => _isProcessing = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentUserId = currentUser.uid;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final firestore = FirebaseFirestore.instance;

      final currentUserRef = firestore.collection('users').doc(currentUserId);
      batch.update(currentUserRef, {
        'friendRequestsReceived': FieldValue.arrayRemove([requesterId]),
        'friends': FieldValue.arrayUnion([requesterId]),
      });

      final requesterRef = firestore.collection('users').doc(requesterId);
      batch.update(requesterRef, {
        'friendRequestsSent': FieldValue.arrayRemove([currentUserId]),
        'friends': FieldValue.arrayUnion([currentUserId]),
      });

      await batch.commit();
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Đã chấp nhận kết bạn.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Lỗi khi chấp nhận: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectFriendRequest(String requesterId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || !mounted) return;
    setState(() => _isProcessing = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentUserId = currentUser.uid;

    try {
      final batch = FirebaseFirestore.instance.batch();
      final firestore = FirebaseFirestore.instance;

      final currentUserRef = firestore.collection('users').doc(currentUserId);
      batch.update(currentUserRef, {
        'friendRequestsReceived': FieldValue.arrayRemove([requesterId]),
      });

      final requesterRef = firestore.collection('users').doc(requesterId);
      batch.update(requesterRef, {
        'friendRequestsSent': FieldValue.arrayRemove([currentUserId]),
      });

      await batch.commit();
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Đã từ chối kết bạn.')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Lỗi khi từ chối: $e')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- THÊM MỚI: HÀM XỬ LÝ TEAM INVITATION (Mời vào đội) ---
  Future<void> _acceptTeamInvitation(String invitationId, String teamId) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || !mounted) return;
    setState(() => _isProcessing = true);

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final currentUserId = currentUser.uid;
    final firestore = FirebaseFirestore.instance;

    try {
      // Dùng Transaction để ĐỌC (check team full) rồi GHI an toàn
      await firestore.runTransaction((transaction) async {
        final teamRef = firestore.collection('teams').doc(teamId);
        final teamDoc = await transaction.get(teamRef);

        if (!teamDoc.exists) {
          throw Exception("Đội này không còn tồn tại.");
        }

        final teamData = teamDoc.data() as Map<String, dynamic>;
        final List<String> members = List<String>.from(
          teamData['members'] ?? [],
        );
        final int maxMembers =
            (teamData['memberCount'] as num?)?.toInt() ?? 5; // Lấy từ logic cũ

        // CHECK QUAN TRỌNG: Kiểm tra xem team có đầy không
        if (members.length >= maxMembers) {
          throw Exception("Đội này đã đầy.");
        }

        // Nếu chưa full, tiếp tục
        final inviteRef = firestore
            .collection('teamInvitations')
            .doc(invitationId);

        // 1. Thêm user vào mảng members của đội
        transaction.update(teamRef, {
          'members': FieldValue.arrayUnion([currentUserId]),
        });

        // 2. Cập nhật status của lời mời
        transaction.update(inviteRef, {'status': 'accepted'});
      });

      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Đã gia nhập đội.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Lỗi: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectTeamInvitation(String invitationId) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance
          .collection('teamInvitations')
          .doc(invitationId)
          .update({'status': 'rejected'});

      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Đã từ chối lời mời.')),
      );
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Lỗi: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    return DefaultTabController(
      length: 3, // 3 Tab
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          backgroundColor: Colors.white,
          elevation: 1,
          foregroundColor: Colors.black,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Requests'),
              Tab(text: 'Friends'),
              Tab(text: 'Invitations'),
            ],
          ),
        ),
        // SỬA ĐỔI: Thay body bằng TabBarView
        body: currentUser == null
            ? const Center(child: Text('Please log in to see notifications.'))
            : TabBarView(
                children: [
                  // Tab 1: Team Requests
                  _buildTeamRequestsList(currentUser),
                  // Tab 2: Friend Requests
                  _buildFriendRequestsList(currentUser),
                  // Tab 3: Team Invitations (THÊM MỚI)
                  _buildTeamInvitationsList(currentUser),
                ],
              ),
      ),
    );
  }

  // --- WIDGET CHO TAB 1 (Team Requests - Xin vào đội) ---
  Widget _buildTeamRequestsList(User currentUser) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('joinRequests')
          .where('ownerId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No new team requests.'));
        }

        final requests = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final data = request.data() as Map<String, dynamic>;

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(
                          context,
                        ).style.copyWith(fontSize: 15),
                        children: <TextSpan>[
                          TextSpan(
                            text: data['requesterName'],
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: ' wants to join your team '),
                          TextSpan(
                            text: '"${data['teamName']}"',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _rejectRequest(request.id),
                          child: const Text(
                            'Reject',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _acceptRequest(
                                  request.id,
                                  data['teamId'],
                                  data['requesterId'],
                                ),
                          child: const Text('Accept'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- WIDGET CHO TAB 2 (Friend Requests - Kết bạn) ---
  Widget _buildFriendRequestsList(User currentUser) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong.'));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Center(child: Text('Could not find user data.'));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final List<String> requestUids = List<String>.from(
          data['friendRequestsReceived'] ?? [],
        );

        if (requestUids.isEmpty) {
          return const Center(child: Text('No new friend requests.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: requestUids.length,
          itemBuilder: (context, index) {
            final requesterId = requestUids[index];
            return _FriendRequestTile(
              requesterId: requesterId,
              isProcessing: _isProcessing,
              onAccept: () => _acceptFriendRequest(requesterId),
              onReject: () => _rejectFriendRequest(requesterId),
            );
          },
        );
      },
    );
  }

  // --- THÊM MỚI: WIDGET CHO TAB 3 (Team Invitations - Mời vào đội) ---
  Widget _buildTeamInvitationsList(User currentUser) {
    return StreamBuilder<QuerySnapshot>(
      // Truy vấn collection `teamInvitations`
      stream: FirebaseFirestore.instance
          .collection('teamInvitations')
          .where('inviteeId', isEqualTo: currentUser.uid) // Mời BẠN
          .where('status', isEqualTo: 'pending') // Đang chờ
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return const Center(child: Text('Something went wrong.'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No new team invitations.'));
        }

        final invitations = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: invitations.length,
          itemBuilder: (context, index) {
            final invitation = invitations[index];
            final data = invitation.data() as Map<String, dynamic>;
            final String invitationId = invitation.id;
            final String teamId = data['teamId'];

            return Card(
              elevation: 2,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: DefaultTextStyle.of(
                          context,
                        ).style.copyWith(fontSize: 15),
                        children: <TextSpan>[
                          TextSpan(
                            text: data['inviterName'], // Tên người mời
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const TextSpan(text: ' invited you to join team '),
                          TextSpan(
                            text: '"${data['teamName']}"', // Tên đội
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isProcessing
                              ? null
                              : () => _rejectTeamInvitation(invitationId),
                          child: const Text(
                            'Reject',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isProcessing
                              ? null
                              : () =>
                                    _acceptTeamInvitation(invitationId, teamId),
                          child: const Text('Accept'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// --- WIDGET ĐỂ HIỂN THỊ MỘT FRIEND REQUEST ---
// (Giữ nguyên, không thay đổi)
class _FriendRequestTile extends StatelessWidget {
  final String requesterId;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _FriendRequestTile({
    required this.requesterId,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(requesterId)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const CircleAvatar(child: CircularProgressIndicator()),
              title: Container(height: 16, color: Colors.grey.shade200),
              subtitle: Container(height: 12, color: Colors.grey.shade200),
            ),
          );
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final displayName = data['displayName'] ?? 'Unknown User';
        final photoUrl = data['photoURL'] as String?;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundImage: (photoUrl != null)
                      ? NetworkImage(photoUrl)
                      : null,
                  child: (photoUrl == null) ? const Icon(Icons.person) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: DefaultTextStyle.of(
                            context,
                          ).style.copyWith(fontSize: 15),
                          children: [
                            TextSpan(
                              text: displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const TextSpan(text: ' wants to be your friend.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isProcessing ? null : onReject,
                            child: const Text(
                              'Reject',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isProcessing ? null : onAccept,
                            child: const Text('Accept'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
