import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'member_list_screen.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'chat_screen.dart';
import 'package:rxdart/rxdart.dart';
import 'package:image_cropper/image_cropper.dart';
import 'create_event_screen.dart';
import 'event_of_team_screen.dart';
import '../widgets/custom_dropdown_widget.dart';
import 'schedule_team_screen.dart';
import 'review_team_screen.dart';

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

// 1. Thêm SingleTickerProviderStateMixin để dùng animation cho TabController
class _TeamScreenState extends State<TeamScreen>
    with SingleTickerProviderStateMixin {
  String? _expandedTeamId;

  final _formKey = GlobalKey<FormState>();
  final _teamNameController = TextEditingController();
  final _memberCountController = TextEditingController();
  final _joinTeamIdController = TextEditingController();

  // 2. Khai báo TabController
  late TabController _tabController;

  final List<String> _sports = [
    'Bóng đá',
    'Bóng chuyền',
    'Bóng rổ',
    'Bóng bàn',
    'Cầu lông',
    'Tennis',
  ];

  @override
  void initState() {
    super.initState();
    // 3. Khởi tạo TabController và lắng nghe thay đổi
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      // Khi tab thay đổi, gọi setState để rebuild lại nút FloatingActionButton
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _teamNameController.dispose();
    _memberCountController.dispose();
    _joinTeamIdController.dispose();
    _tabController.dispose(); // Dispose controller
    super.dispose();
  }

  // ... (Giữ nguyên các hàm logic: _showAddOptions, _showJoinTeamDialog, _handleJoinTeam, v.v...)
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

  void _showCreateTeamDialog() {
    String? selectedSportInDialog;

    showDialog(
      context: context,
      builder: (BuildContext context) {
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
                      final sport = selectedSportInDialog!;

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
      final imagePicker = ImagePicker();
      final XFile? pickedFile = await imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

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

      if (croppedFile == null) return;

      File imageFile = File(croppedFile.path);

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
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Team image updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
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
    // 4. Xóa DefaultTabController, sử dụng controller thủ công trong Scaffold
    return Scaffold(
      backgroundColor: kWhiteColor,
      appBar: AppBar(
        title: const Text(
          'Communication',
          style: TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 24,
          ),
        ),

        bottom: TabBar(
          controller: _tabController, // Gán controller
          labelColor: kAccentColor,
          unselectedLabelColor: kGreyColor,
          indicatorColor: kAccentColor,
          tabs: const [
            Tab(text: 'Team'),
            Tab(text: 'Individual'),
          ],
        ),
        backgroundColor: kWhiteColor,
        elevation: 0,
      ),
      body: TabBarView(
        controller: _tabController, // Gán controller
        children: [_buildTeamList(), const _IndividualReviewTab()],
      ),
      // 5. Kiểm tra index để ẩn hiện FloatingActionButton
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: _showAddOptions,
              backgroundColor: kAccentColor,
              child: const Icon(Icons.add, color: kWhiteColor),
            )
          : null, // Trả về null để ẩn nút
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
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.groups_outlined, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                const Text(
                  'You are not a member of any team',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create or join one!',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final teams = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: kDefaultPadding,
            vertical: kSmallPadding,
          ),
          itemCount: teams.length,
          itemBuilder: (context, index) {
            final teamDoc = teams[index];
            final teamData = teamDoc.data() as Map<String, dynamic>;
            final teamId = teamDoc.id;
            final teamName = teamData['teamName'] ?? 'No Name';
            final isOwner = currentUser.uid == teamData['ownerId'];
            final isExpanded = _expandedTeamId == teamId;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: TeamCard(
                teamId: teamId,
                teamName: teamName,
                sport: teamData['sport'] ?? 'No Sport',
                imageUrl: teamData['imageUrl'] ?? '',
                showDetails: isExpanded,
                isOwner: isOwner,
                onTap: () {
                  setState(() {
                    if (_expandedTeamId == teamId) {
                      _expandedTeamId = null;
                    } else {
                      _expandedTeamId = teamId;
                    }
                  });
                },
                onShowId: () => _showTeamIdDialog(teamId),
                onDelete: () => _deleteTeam(teamId, teamName),
                onUpdateImage: () => _updateTeamImage(teamId),
              ),
            );
          },
        );
      },
    );
  }
}

class TeamCard extends StatelessWidget {
  final String teamId;
  final String teamName;
  final String sport;
  final String imageUrl;
  final bool showDetails;
  final bool isOwner;
  final VoidCallback onTap;
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
    required this.onTap,
    required this.onShowId,
    required this.onDelete,
    required this.onUpdateImage,
  });

  Widget _buildChatIconWithBadge(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const _DetailIcon(icon: Icons.chat_bubble_outline, label: 'Chat');
    }

    final teamStream = FirebaseFirestore.instance
        .collection('teams')
        .doc(teamId)
        .snapshots();

    final userReadStream = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('teamReadStatus')
        .doc(teamId)
        .snapshots();

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
            if (!userReadDoc.exists) {
              hasNewMessage = true;
            } else {
              final userReadData = userReadDoc.data() as Map<String, dynamic>?;
              final lastReadTimestamp =
                  userReadData?['lastReadTimestamp'] as Timestamp?;
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
      {'icon': Icons.rate_review_outlined, 'label': 'Reviews'},
    ];

    return Card(
      elevation: showDetails ? 4.0 : 1.0,
      shadowColor: showDetails
          ? kAccentColor.withOpacity(0.3)
          : Colors.grey.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.0),
        side: BorderSide(
          color: showDetails
              ? kAccentColor.withOpacity(0.3)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!showDetails)
                _buildCompactView()
              else
                _buildExpandedView(context, detailItems),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactView() {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12.0),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              height: 70,
              width: 70,
              fit: BoxFit.cover,
              placeholder: (context, url) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.image, color: Colors.grey),
              ),
              errorWidget: (context, url, error) => Container(
                color: Colors.grey[200],
                child: const Icon(Icons.error, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  teamName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.sports, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      sport,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (isOwner)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: kAccentColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Owner',
                      style: TextStyle(
                        fontSize: 11,
                        color: kAccentColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.keyboard_arrow_down, color: Colors.grey[400]),
        ],
      ),
    );
  }

  Widget _buildExpandedView(
    BuildContext context,
    List<Map<String, dynamic>> detailItems,
  ) {
    return Padding(
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
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: kPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.sports, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          sport,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Icon(Icons.keyboard_arrow_up, color: Colors.grey[400]),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'show_id') {
                        onShowId();
                      } else if (value == 'delete') {
                        onDelete();
                      }
                    },
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'show_id',
                            child: Row(
                              children: [
                                Icon(Icons.vpn_key_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Show Team ID'),
                              ],
                            ),
                          ),
                          if (isOwner)
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  SizedBox(width: 12),
                                  Text(
                                    'Delete Team',
                                    style: TextStyle(color: Colors.red),
                                  ),
                                ],
                              ),
                            ),
                        ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12.0),
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[200]),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
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
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.edit,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16.0),
          const Divider(height: 1),
          const SizedBox(height: 12.0),
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: kPrimaryColor,
            ),
          ),
          const SizedBox(height: 12.0),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: detailItems.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10.0,
              mainAxisSpacing: 12.0,
              childAspectRatio: 1.0,
            ),
            itemBuilder: (context, index) {
              final item = detailItems[index];

              return GestureDetector(
                onTap: () {
                  if (item['label'] == 'Members') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MemberListScreen(teamId: teamId),
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
                  } else if (item['label'] == 'Schedule') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ScheduleTeamScreen(
                          teamId: teamId,
                          teamName: teamName,
                          isUserOwner: isOwner,
                        ),
                      ),
                    );
                  } else if (item['label'] == 'Reviews') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ReviewTeamScreen(teamId: teamId),
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

// --- WIDGET TAB INDIVIDUAL REVIEW ---
class _IndividualReviewTab extends StatelessWidget {
  const _IndividualReviewTab();

  Color _getScoreColor(int score) {
    if (score >= 90) return Colors.green;
    if (score >= 75) return Colors.blue;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  String _getReasonText(String reason) {
    switch (reason) {
      case 'good':
        return 'Đúng hẹn';
      case 'late':
        return 'Đến muộn';
      case 'no_show':
        return 'Vắng mặt';
      default:
        return reason;
    }
  }

  Color _getReasonColor(String reason) {
    switch (reason) {
      case 'good':
        return Colors.green;
      case 'late':
        return Colors.orange;
      case 'no_show':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Center(child: Text("Vui lòng đăng nhập để xem đánh giá."));
    }

    return Container(
      color: Colors.grey[100],
      child: SingleChildScrollView(
        child: Column(
          children: [
            _buildUserHeader(user.uid),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Lịch sử đánh giá cá nhân",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            _buildReviewsList(user.uid),
          ],
        ),
      ),
    );
  }

  Widget _buildUserHeader(String uid) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null)
          return const Center(child: Text("Không tìm thấy dữ liệu User"));

        final int reputationScore = data['reputationScore'] ?? 100;
        final int goodCount = data['goodCount'] ?? 0;
        final int lateCount = data['lateCount'] ?? 0;
        final int noShowCount = data['noShowCount'] ?? 0;
        final String displayName = data['displayName'] ?? 'User';
        final String photoUrl =
            data['photoURL'] ?? ''; // Sửa từ photoUrl thành photoURL

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey.shade200),
                      image: photoUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(photoUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, size: 40, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getScoreColor(
                              reputationScore,
                            ).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "Điểm uy tín: $reputationScore",
                            style: TextStyle(
                              color: _getScoreColor(reputationScore),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem("Đúng hẹn", goodCount, Colors.green),
                  _buildStatItem("Đến muộn", lateCount, Colors.orange),
                  _buildStatItem("Vắng mặt", noShowCount, Colors.red),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsList(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('reviews')
          .where('targetId', isEqualTo: uid)
          .where('targetType', isEqualTo: 'user')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.only(top: 20),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            child: Column(
              children: const [
                Icon(Icons.rate_review_outlined, size: 50, color: Colors.grey),
                SizedBox(height: 10),
                Text(
                  "Chưa có đánh giá cá nhân nào.",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            return _buildReviewItem(data);
          },
        );
      },
    );
  }

  Widget _buildReviewItem(Map<String, dynamic> reviewData) {
    final String reason = reviewData['reason'] ?? 'good';
    final String comment = reviewData['comment'] ?? '';
    final String reviewerId = reviewData['reviewerId'] ?? '';
    final Timestamp? createdAt = reviewData['createdAt'];

    final String dateString = createdAt != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
        : 'Unknown Date';

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(reviewerId)
          .get(),
      builder: (context, userSnapshot) {
        String reviewerName = "Người dùng ẩn danh";
        String? reviewerImage;

        if (userSnapshot.hasData && userSnapshot.data!.exists) {
          final userData = userSnapshot.data!.data() as Map<String, dynamic>;
          reviewerName = userData['displayName'] ?? reviewerName;
          reviewerImage =
              userData['photoURL']; // Sửa từ photoUrl thành photoURL
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage:
                        (reviewerImage != null && reviewerImage.isNotEmpty)
                        ? NetworkImage(reviewerImage)
                        : null,
                    backgroundColor: Colors.blue.shade100,
                    child: (reviewerImage == null || reviewerImage.isEmpty)
                        ? Text(
                            reviewerName.isNotEmpty
                                ? reviewerName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(color: Colors.blue),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reviewerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          dateString,
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _getReasonColor(reason).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _getReasonColor(reason).withOpacity(0.3),
                      ),
                    ),
                    child: Text(
                      _getReasonText(reason),
                      style: TextStyle(
                        color: _getReasonColor(reason),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (comment.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    comment,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
