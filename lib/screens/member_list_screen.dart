import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';

// Giả sử bạn có các hằng số màu này, hoặc bạn có thể thay thế trực tiếp
const Color kPrimaryColor = Color.fromRGBO(7, 7, 112, 1);

class MemberListScreen extends StatefulWidget {
  final String teamId;

  const MemberListScreen({super.key, required this.teamId});

  @override
  State<MemberListScreen> createState() => _MemberListScreenState();
}

class _MemberListScreenState extends State<MemberListScreen> {
  late Future<List<Map<String, dynamic>>> _membersFuture;

  @override
  void initState() {
    super.initState();
    _membersFuture = _fetchMembersData();
  }

  // Hàm để lấy dữ liệu thành viên
  Future<List<Map<String, dynamic>>> _fetchMembersData() async {
    try {
      // 1. Lấy document của team để có danh sách ID thành viên
      final teamDoc = await FirebaseFirestore.instance
          .collection('teams')
          .doc(widget.teamId)
          .get();

      if (!teamDoc.exists) {
        return [];
      }

      final teamData = teamDoc.data()!;
      final List<String> memberIds = List<String>.from(
        teamData['members'] ?? [],
      );

      if (memberIds.isEmpty) {
        return [];
      }

      // 2. Dùng `whereIn` để lấy thông tin của tất cả thành viên trong 1 query
      // Lưu ý: `whereIn` chỉ hỗ trợ tối đa 30 giá trị mỗi lần. Nếu team có nhiều hơn, bạn cần chia nhỏ query.
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: memberIds)
          .get();

      final membersData = usersSnapshot.docs.map((doc) => doc.data()).toList();

      // Tìm ownerId để đánh dấu
      final ownerId = teamData['ownerId'];
      for (var member in membersData) {
        if (member['uid'] == ownerId) {
          member['isOwner'] = true;
        } else {
          member['isOwner'] = false;
        }
      }

      return membersData;
    } catch (e) {
      print('Error fetching members: $e');
      throw Exception('Failed to load members');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Members'),
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: kPrimaryColor,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _membersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No members found in this team.'));
          }

          final members = snapshot.data!;

          return ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, index) {
              final member = members[index];
              final isOwner = member['isOwner'] ?? false;

              return ListTile(
                leading: CircleAvatar(
                  radius: 25,
                  backgroundImage:
                      (member['photoURL'] != null &&
                          member['photoURL'].isNotEmpty)
                      ? CachedNetworkImageProvider(member['photoURL'])
                      : null,
                  child:
                      (member['photoURL'] == null || member['photoURL'].isEmpty)
                      ? const Icon(Icons.person)
                      : null,
                ),
                title: Text(
                  member['displayName'] ?? 'No Name',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(member['email'] ?? 'No email'),
                trailing: isOwner
                    ? Chip(
                        label: const Text(
                          'Owner',
                          style: TextStyle(fontSize: 12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                      )
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
