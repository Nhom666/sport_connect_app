import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'package:geolocator/geolocator.dart';
import 'user_profile_screen.dart';
import '../utils/constants.dart';

class AllPartnersScreen extends StatefulWidget {
  final Position currentPosition;
  const AllPartnersScreen({Key? key, required this.currentPosition})
    : super(key: key);

  @override
  _AllPartnersScreenState createState() => _AllPartnersScreenState();
}

class _AllPartnersScreenState extends State<AllPartnersScreen> {
  final _geo = GeoFlutterFire();
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  Stream<List<DocumentSnapshot>>? _partnersStream;

  // --- THÊM MỚI: Các biến trạng thái cho bộ lọc ---
  String? _selectedSportFilter;
  String? _selectedSkillFilter;
  final List<String> _selectedFreeTimeFilter = [];
  // --- KẾT THÚC THÊM MỚI ---

  @override
  void initState() {
    super.initState();
    _setupPartnerStream();
  }

  void _setupPartnerStream() {
    CollectionReference usersRef = _firestore.collection('users');
    GeoFirePoint center = _geo.point(
      latitude: widget.currentPosition.latitude,
      longitude: widget.currentPosition.longitude,
    );

    _partnersStream = _geo
        .collection(collectionRef: usersRef)
        .within(
          center: center,
          radius: 50, // Bán kính 50km
          field: 'position',
          strictMode: true,
        );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kWhiteColor,
      appBar: AppBar(
        backgroundColor: kWhiteColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kPrimaryColor),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Partners Near You',
          style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: kPrimaryColor),
            onPressed: _showFilterDialog,
          ),
        ],
      ),
      body: _buildPartnersList(),
    );
  }

  Widget _buildPartnersList() {
    if (_partnersStream == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _partnersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final allPartners = snapshot.data ?? [];

        // --- THAY ĐỔI: Sử dụng biến state thay vì widget.<prop> ---
        final filteredPartners = allPartners.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return false;
          if (doc.id == _auth.currentUser?.uid) return false;

          if (_selectedSportFilter != null) {
            // <-- THAY ĐỔI
            final String userSport = data['favoriteSport'] ?? '';
            if (userSport != _selectedSportFilter) return false; // <-- THAY ĐỔI
          }
          if (_selectedSkillFilter != null) {
            // <-- THAY ĐỔI
            final String userLevel = data['level'] ?? '';
            if (userLevel != _selectedSkillFilter) return false; // <-- THAY ĐỔI
          }
          if (_selectedFreeTimeFilter.isNotEmpty) {
            // <-- THAY ĐỔI
            final userSchedules = List<String>.from(
              data['freeSchedules'] ?? [],
            );
            if (!_selectedFreeTimeFilter.any(
              // <-- THAY ĐỔI
              (time) => userSchedules.contains(time),
            )) {
              return false;
            }
          }
          return true;
        }).toList();
        // --- KẾT THÚC THAY ĐỔI ---

        if (filteredPartners.isEmpty) {
          return const Center(
            child: Text('No partners found matching your criteria.'),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          itemCount: filteredPartners.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final partnerDoc = filteredPartners[index];
            return _buildPartnerListTile(partnerDoc);
          },
        );
      },
    );
  }

  Widget _buildPartnerListTile(DocumentSnapshot userDoc) {
    final userData = userDoc.data() as Map<String, dynamic>;
    final String name = userData['displayName'] ?? 'Sporty User';
    final String photoUrl =
        userData['photoURL'] ?? 'https://via.placeholder.com/150';
    final String level = userData['level'] ?? 'N/A';
    final String sport = userData['favoriteSport'] ?? 'No sport';

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: photoUrl,
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          placeholder: (context, url) => Container(color: Colors.grey[200]),
          errorWidget: (context, url, error) =>
              const Icon(Icons.person, size: 50),
        ),
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        '$sport - $level',
        style: TextStyle(color: Colors.grey[600]),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: userDoc.id),
          ),
        );
      },
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        // <-- Builder của showModalBottomSheet

        // --- START: DI CHUYỂN CÁC BIẾN RA ĐÂY ---
        // Các biến này giờ sẽ được khởi tạo 1 LẦN DUY NHẤT
        // khi dialog mở ra và sẽ tồn tại qua các lần gọi setDialogState.
        String? localSport = _selectedSportFilter;
        String? localSkill = _selectedSkillFilter;
        List<String> localFreeTime = List.from(_selectedFreeTimeFilter);
        // --- END: DI CHUYỂN ---

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            // --- XÓA CÁC BIẾN NÀY KHỎI ĐÂY ---
            // String? localSport = _selectedSportFilter; (ĐÃ XÓA)
            // String? localSkill = _selectedSkillFilter; (ĐÃ XÓA)
            // List<String> localFreeTime = List.from(_selectedFreeTimeFilter); (ĐÃ XÓA)
            // --- KẾT THÚC XÓA ---

            final List<String> allSports = [
              'Bóng đá',
              'Bóng chuyền',
              'Bóng rổ',
              'Bóng bàn',
              'Cầu lông',
              'Tennis',
            ];
            final List<String> skillLevels = ['Sơ cấp', 'Trung cấp', 'Cao cấp'];
            final List<String> freeTimeSlots = [
              'Cuối tuần',
              'Tối (T2-T6)',
              'Sáng (T2-T6)',
              'Chiều (T2-T6)',
            ];

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter Partners',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Sport',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Wrap(
                      spacing: 8.0,
                      children: allSports.map((sport) {
                        return ChoiceChip(
                          label: Text(sport),
                          selectedColor: kAccentColor.withOpacity(0.8),
                          selected: localSport == sport, // <-- Giờ đã đúng
                          onSelected: (selected) {
                            setDialogState(() {
                              localSport = selected ? sport : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Skill Level',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Wrap(
                      spacing: 8.0,
                      children: skillLevels.map((skill) {
                        return ChoiceChip(
                          label: Text(skill),
                          selectedColor: kAccentColor.withOpacity(0.8),
                          selected: localSkill == skill, // <-- Giờ đã đúng
                          onSelected: (selected) {
                            setDialogState(() {
                              localSkill = selected ? skill : null;
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Availability',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Wrap(
                      spacing: 8.0,
                      children: freeTimeSlots.map((time) {
                        final isSelected = localFreeTime.contains(time);
                        return FilterChip(
                          label: Text(time),
                          selectedColor: kAccentColor.withOpacity(0.8),
                          selected: isSelected, // <-- Giờ đã đúng
                          onSelected: (selected) {
                            setDialogState(() {
                              if (selected) {
                                localFreeTime.add(time);
                              } else {
                                localFreeTime.remove(time);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setDialogState(() {
                                localSport = null;
                                localSkill = null;
                                localFreeTime.clear();
                              });
                              setState(() {
                                _selectedSportFilter = null;
                                _selectedSkillFilter = null;
                                _selectedFreeTimeFilter.clear();
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Reset'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _selectedSportFilter = localSport;
                                _selectedSkillFilter = localSkill;
                                _selectedFreeTimeFilter.clear();
                                _selectedFreeTimeFilter.addAll(localFreeTime);
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('Apply Filters'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kAccentColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
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
