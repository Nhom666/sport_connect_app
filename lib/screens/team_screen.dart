import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'member_list_screen.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'chat_screen.dart';
import 'package:rxdart/rxdart.dart';
import 'package:image_cropper/image_cropper.dart';
import 'create_event_screen.dart';
import 'event_of_team_screen.dart';
import '../widgets/custom_dropdown_widget.dart'; // Đã thêm import này

// Constants
const Color kPrimaryColor = Color.fromRGBO(7, 7, 112, 1);
const Color kAccentColor = Colors.blue;
const Color kWhiteColor = Colors.white;
const Color kGreyColor = Colors.grey;
const double kDefaultPadding = 16.0;
const double kSmallPadding = 8.0;
final BorderRadius kDefaultBorderRadius = BorderRadius.circular(12.0);

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});

  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  String? _expandedTeamId; //teamId của team đang mở rộng

  final _formKey = GlobalKey<FormState>();
  final _teamNameController = TextEditingController();
  final _memberCountController = TextEditingController();
  // Đã xóa _sportController vì dùng dropdown
  final _joinTeamIdController = TextEditingController();

  // Danh sách môn thể thao (giống bên edit_profile_screen)
  final List<String> _sports = [
    'Bóng đá',
    'Bóng chuyền',
    'Bóng rổ',
    'Bóng bàn',
    'Cầu lông',
    'Tennis',
  ];

  @override
  void dispose() {
    _teamNameController.dispose();
    _memberCountController.dispose();
    // _sportController.dispose(); // Đã xóa
    _joinTeamIdController.dispose();
    super.dispose();
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (BuildContext context) {
        return Wrap(
          children: <Widget>[
            ListTile(
              leading: const Icon(
                Icons.group_add_outlined,
                color: kAccentColor,
              ),
              title: const Text('Create Team'),
              onTap: () {
                Navigator.of(context).pop();
                _showCreateTeamDialog();
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.person_add_alt_1_outlined,
                color: kAccentColor,
              ),
              title: const Text('Join Team'),
              onTap: () {
                Navigator.of(context).pop();
                _showJoinTeamDialog();
              },
            ),
          ],
        );
      },
    );
  }

  void _showJoinTeamDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
        title: const Text('Join a Team'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _joinTeamIdController,
              decoration: const InputDecoration(
                labelText: 'Enter Team ID',
                prefixIcon: Icon(Icons.vpn_key_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(onPressed: _handleJoinTeam, child: const Text('Join')),
        ],
      ),
    );
  }

  Future<void> _handleJoinTeam() async {
    final teamId = _joinTeamIdController.text.trim();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (teamId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a Team ID.')));
      return;
    }

    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to join a team.')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      final teamDocRef = FirebaseFirestore.instance
          .collection('teams')
          .doc(teamId);
      final teamDoc = await teamDocRef.get();

      if (!mounted) return;

      if (!teamDoc.exists) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team not found. Please check the ID.')),
        );
        return;
      }

      final teamData = teamDoc.data()!;
      final members = List<String>.from(teamData['members'] ?? []);
      if (members.contains(currentUser.uid)) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You are already in this team.')),
        );
        return;
      }

      final requestQuery = await FirebaseFirestore.instance
          .collection('joinRequests')
          .where('teamId', isEqualTo: teamId)
          .where('requesterId', isEqualTo: currentUser.uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (!mounted) return;

      if (requestQuery.docs.isNotEmpty) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your request to join this team is already pending.'),
          ),
        );
        return;
      }

      await FirebaseFirestore.instance.collection('joinRequests').add({
        'teamId': teamId,
        'teamName': teamData['teamName'],
        'requesterId': currentUser.uid,
        'requesterName':
            currentUser.displayName ?? currentUser.email ?? 'A User',
        'ownerId': teamData['ownerId'],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.of(context).pop();
      Navigator.of(context).pop();
      _joinTeamIdController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Your request to join "${teamData['teamName']}" has been sent!',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send request: $e')));
    }
  }

  // === ĐÃ CHỈNH SỬA HÀM NÀY ĐỂ SỬ DỤNG DROPDOWN ===
  void _showCreateTeamDialog() {
    // Biến cục bộ lưu sport được chọn trong dialog
    String? selectedSportInDialog;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Sử dụng StatefulBuilder để cập nhật UI bên trong Dialog (cho Dropdown)
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
              title: const Text('Create New Team'),
              content: Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextFormField(
                        controller: _teamNameController,
                        decoration: const InputDecoration(
                          labelText: 'Team Name',
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a team name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _memberCountController,
                        decoration: const InputDecoration(
                          labelText: 'Number of Members',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter the number of members';
                          }
                          if (int.tryParse(value) == null) {
                            return 'Please enter a valid number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      // Thay thế TextFormField sport bằng CustomDropdownWidget
                      CustomDropdownWidget(
                        title: 'Sport',
                        items: _sports,
                        selectedItem: selectedSportInDialog,
                        onChanged: (value) {
                          setStateDialog(() {
                            selectedSportInDialog = value;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  child: const Text('Create'),
                  onPressed: () async {
                    if (_formKey.currentState!.validate()) {
                      // Kiểm tra thủ công xem đã chọn sport chưa
                      if (selectedSportInDialog == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please select a sport'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      final user = FirebaseAuth.instance.currentUser;
                      if (user == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'You must be logged in to create a team',
                            ),
                          ),
                        );
                        return;
                      }

                      final teamName = _teamNameController.text;
                      final memberCount =
                          int.tryParse(_memberCountController.text) ?? 0;
                      final sport = selectedSportInDialog!; // Lấy từ dropdown

                      try {
                        await FirebaseFirestore.instance.collection('teams').add({
                          'teamName': teamName,
                          'memberCount': memberCount,
                          'sport': sport,
                          'imageUrl':
                              'https://via.placeholder.com/400x200.png?text=$teamName',
                          'ownerId': user.uid,
                          'members': [user.uid],
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('$teamName created successfully!'),
                          ),
                        );
                        _formKey.currentState!.reset();
                        _teamNameController.clear();
                        _memberCountController.clear();
                        // Không cần clear sport controller nữa
                        Navigator.of(context).pop();
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to create team: $e')),
                        );
                      }
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
  // =================================================

  void _showTeamIdDialog(String teamId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
        title: const Text('Team ID'),
        content: SelectableText(
          teamId,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: teamId));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Team ID copied to clipboard!')),
              );
            },
            child: const Text('Copy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _deleteTeam(String teamId, String teamName) async {
    final bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
        title: const Text('Delete Team'),
        content: Text(
          'Are you sure you want to delete "$teamName"? This action cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      try {
        await FirebaseFirestore.instance
            .collection('teams')
            .doc(teamId)
            .delete();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"$teamName" has been deleted.')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete team: $e')));
      }
    }
  }

  Future<void> _updateTeamImage(String teamId) async {
    try {
      // 1. Chọn ảnh từ thư viện
      final imagePicker = ImagePicker();
      final XFile? pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile == null) return; // Người dùng hủy

      // 2. Mở màn hình cắt ảnh
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 100,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Image',
            toolbarColor: kPrimaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
            lockAspectRatio: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.original,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Image',
            aspectRatioPresets: [
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.square,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.original,
            ],
          ),
        ],
      );

      if (croppedFile == null) return; // Người dùng hủy ở màn hình cắt ảnh

      // 3. Dùng file đã được cắt để tải lên
      File imageFile = File(croppedFile.path);

      // Hiển thị loading
      showDialog(
        context: context,
        builder: (context) => const Center(child: CircularProgressIndicator()),
        barrierDismissible: false,
      );

      final storageRef = FirebaseStorage.instance.ref().child(
        'team_images/$teamId/cover.jpg',
      );
      await storageRef.putFile(imageFile);
      final String downloadUrl = await storageRef.getDownloadURL();

      await FirebaseFirestore.instance.collection('teams').doc(teamId).update({
        'imageUrl': downloadUrl,
      });

      if (!mounted) return;
      Navigator.of(context).pop(); // Tắt loading
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Team image updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Tắt loading nếu có lỗi
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update image: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: kWhiteColor,
        appBar: AppBar(
          title: const Text(
            'Your Team',
            style: TextStyle(
              color: kPrimaryColor,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          actions: [
            IconButton(icon: const Icon(Icons.search), onPressed: () {}),
            IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
          ],
          bottom: const TabBar(
            labelColor: kAccentColor,
            unselectedLabelColor: kGreyColor,
            indicatorColor: kAccentColor,
            tabs: [
              Tab(text: 'Team'),
              Tab(text: 'Individual'),
            ],
          ),
          backgroundColor: kWhiteColor,
          elevation: 0,
        ),
        body: TabBarView(
          children: [
            _buildTeamList(),
            const Center(child: Text('Individual')),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _showAddOptions,
          backgroundColor: kAccentColor,
          child: const Icon(Icons.add, color: kWhiteColor),
        ),
      ),
    );
  }

  Widget _buildTeamList() {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Center(child: Text("Please log in to see your teams."));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('teams')
          .where('members', arrayContains: currentUser.uid)
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          print(snapshot.error);
          return const Center(
            child: Text(
              'Something went wrong. Make sure you have created the Firestore index.',
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'You are not a member of any team. Create or join one!',
            ),
          );
        }

        final teams = snapshot.data!.docs;

        // Tự động mở team đầu tiên nếu chưa có team nào được chọn
        if (_expandedTeamId == null && teams.isNotEmpty) {
          _expandedTeamId = teams.first.id;
        }

        return ListView.builder(
          padding: const EdgeInsets.all(kSmallPadding),
          itemCount: teams.length,
          itemBuilder: (context, index) {
            final teamDoc = teams[index];
            final teamData = teamDoc.data() as Map<String, dynamic>;
            final teamId = teamDoc.id;
            final teamName = teamData['teamName'] ?? 'No Name';
            final isOwner = currentUser.uid == teamData['ownerId'];

            return GestureDetector(
              onTap: () {
                setState(() {
                  // Nếu bấm vào card đang mở thì đóng lại, nếu không thì mở card mới
                  if (_expandedTeamId == teamId) {
                    _expandedTeamId = null; // Đóng lại
                  } else {
                    _expandedTeamId = teamId; // Mở ra
                  }
                });
              },
              child: Padding(
                padding: const EdgeInsets.only(bottom: kDefaultPadding),
                child: TeamCard(
                  teamId: teamId,
                  teamName: teamName,
                  sport: teamData['sport'] ?? 'No Sport',
                  imageUrl: teamData['imageUrl'] ?? '',
                  showDetails: _expandedTeamId == teamId,
                  isOwner: isOwner,
                  onShowId: () => _showTeamIdDialog(teamId),
                  onDelete: () => _deleteTeam(teamId, teamName),
                  onUpdateImage: () => _updateTeamImage(teamId),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// Hoàn thiện lớp TeamCard
class TeamCard extends StatelessWidget {
  final String teamId;
  final String teamName;
  final String sport;
  final String imageUrl;
  final bool showDetails;
  final bool isOwner;
  final VoidCallback onShowId;
  final VoidCallback onDelete;
  final VoidCallback onUpdateImage;

  const TeamCard({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.sport,
    required this.imageUrl,
    this.showDetails = false,
    required this.isOwner,
    required this.onShowId,
    required this.onDelete,
    required this.onUpdateImage,
  });

  // Widget riêng cho icon Chat để quản lý badge
  Widget _buildChatIconWithBadge(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const _DetailIcon(icon: Icons.chat_bubble_outline, label: 'Chat');
    }

    // Stream 1: Lắng nghe team document để lấy lastMessageTimestamp
    final teamStream = FirebaseFirestore.instance
        .collection('teams')
        .doc(teamId)
        .snapshots();

    // Stream 2: Lắng nghe user read status để lấy lastReadTimestamp
    final userReadStream = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('teamReadStatus')
        .doc(teamId)
        .snapshots();

    // Kết hợp 2 stream bằng rxdart
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: Rx.combineLatest2(
        teamStream,
        userReadStream,
        (teamDoc, userDoc) => [teamDoc, userDoc],
      ),
      builder: (context, snapshot) {
        bool hasNewMessage = false;

        if (snapshot.hasData && snapshot.data!.length == 2) {
          final teamData = snapshot.data![0].data() as Map<String, dynamic>?;
          final userReadDoc = snapshot.data![1];

          final lastMessageTimestamp =
              teamData?['lastMessageTimestamp'] as Timestamp?;

          if (lastMessageTimestamp != null) {
            // Nếu user chưa bao giờ đọc chat này
            if (!userReadDoc.exists) {
              hasNewMessage = true;
            } else {
              final userReadData = userReadDoc.data() as Map<String, dynamic>?;
              final lastReadTimestamp =
                  userReadData?['lastReadTimestamp'] as Timestamp?;
              // Nếu tin nhắn cuối cùng mới hơn lần đọc cuối cùng
              if (lastReadTimestamp == null ||
                  lastMessageTimestamp.compareTo(lastReadTimestamp) > 0) {
                hasNewMessage = true;
              }
            }
          }
        }

        return _DetailIcon(
          icon: Icons.chat_bubble_outline,
          label: 'Chat',
          hasBadge: hasNewMessage,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> detailItems = [
      {'icon': Icons.groups_outlined, 'label': 'Members'},
      {'icon': Icons.chat_bubble_outline, 'label': 'Chat'},
      {
        'icon': Icons.calendar_today_outlined,
        'label': 'Schedule',
        'hasBadge': false,
      },
      {'icon': Icons.add_circle_outline, 'label': 'Create Event'},
      {'icon': Icons.event_available_outlined, 'label': 'Events'},
      {'icon': Icons.assessment_outlined, 'label': 'Statistics'},
    ];

    return Card(
      elevation: 2.0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teamName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(sport, style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    if (value == 'show_id')
                      onShowId();
                    else if (value == 'delete')
                      onDelete();
                  },
                  itemBuilder: (BuildContext context) =>
                      <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'show_id',
                          child: ListTile(
                            leading: Icon(Icons.vpn_key_outlined),
                            title: Text('Show Team ID'),
                          ),
                        ),
                        if (isOwner)
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: ListTile(
                              leading: Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              title: Text(
                                'Delete Team',
                                style: TextStyle(color: Colors.red),
                              ),
                            ),
                          ),
                      ],
                ),
              ],
            ),
            const SizedBox(height: 8.0),
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8.0),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey[200]),
                    errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
                  ),
                ),
                if (isOwner)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: InkWell(
                      onTap: onUpdateImage,
                      borderRadius: BorderRadius.circular(50),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (showDetails) ...[
              const SizedBox(height: 16.0),
              const Text(
                'View details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16.0),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: detailItems.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8.0,
                  mainAxisSpacing: 16.0,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
                  final item = detailItems[index];

                  return GestureDetector(
                    onTap: () {
                      if (item['label'] == 'Members') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                MemberListScreen(teamId: teamId),
                          ),
                        );
                      } else if (item['label'] == 'Chat') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ChatScreen(teamId: teamId, teamName: teamName),
                          ),
                        );
                      } else if (item['label'] == 'Create Event') {
                        if (isOwner) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CreateEventScreen(
                                preSelectedTeamId: teamId,
                                preSelectedTeamName: teamName,
                              ),
                            ),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Chỉ đội trưởng mới có thể tạo sự kiện cho đội.',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } else if (item['label'] == 'Events') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EventOfTeamScreen(
                              teamId: teamId,
                              teamName: teamName,
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${item['label']} feature is coming soon!',
                            ),
                          ),
                        );
                      }
                    },
                    child: item['label'] == 'Chat'
                        ? _buildChatIconWithBadge(context)
                        : _DetailIcon(
                            icon: item['icon'],
                            label: item['label'],
                            hasBadge: item['hasBadge'] ?? false,
                          ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool hasBadge;

  const _DetailIcon({
    required this.icon,
    required this.label,
    this.hasBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: kAccentColor, size: 28),
            if (hasBadge)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: const Text(
                    '1',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
