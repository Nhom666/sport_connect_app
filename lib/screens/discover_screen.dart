import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'create_event_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geoflutterfire3/geoflutterfire3.dart';
import 'package:geolocator/geolocator.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'all_events_screen.dart';
import 'event_detail_screen.dart';
import 'user_profile_screen.dart';
import 'all_partners_screen.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({Key? key}) : super(key: key);

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen>
    with
        SingleTickerProviderStateMixin,
        AutomaticKeepAliveClientMixin<DiscoverScreen> {
  late TabController _tabController;

  final _geo = GeoFlutterFire();
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Stream<List<DocumentSnapshot>>? _eventsStream;
  Position? _currentPosition;

  Future<void>? _initFuture;

  final CarouselSliderController _eventCarouselController =
      CarouselSliderController();

  Stream<List<DocumentSnapshot>>? _partnersStream;

  // Hàm này khởi tạo stream để lấy user ở gần
  void _setupPartnerStream() {
    if (_currentPosition == null) return;

    CollectionReference usersRef = _firestore.collection('users');
    GeoFirePoint center = _geo.point(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
    );

    _partnersStream = _geo
        .collection(collectionRef: usersRef)
        .within(
          center: center,
          radius: 10, // bán kính 10km
          field: 'position',
          strictMode: true,
        );
  }

  // Hàm này cập nhật vị trí của user hiện tại lên Firestore
  Future<void> _updateUserLocation(Position position) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    String uid = currentUser.uid;
    GeoFirePoint myLocation = _geo.point(
      latitude: position.latitude,
      longitude: position.longitude,
    );

    try {
      await _firestore.collection('users').doc(uid).set({
        'position': myLocation.data,
      }, SetOptions(merge: true));
    } catch (e) {
      print("Failed to update user location: $e");
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initFuture = _getCurrentLocationAndSetupStream();

    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        if (_tabController.index == 0) {
          setState(() {
            _initFuture = _getCurrentLocationAndSetupStream();
          });
        }
      }
    });
  }

  Future<void> _getCurrentLocationAndSetupStream() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled.');
      }
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(
          'Location permissions are permanently denied, we cannot request permissions.',
        );
      }
      _currentPosition = await Geolocator.getCurrentPosition();

      if (_currentPosition != null) {
        await _updateUserLocation(_currentPosition!);
        _setupPartnerStream();

        CollectionReference eventsRef = _firestore.collection('events');
        GeoFirePoint center = _geo.point(
          latitude: _currentPosition!.latitude,
          longitude: _currentPosition!.longitude,
        );
        _eventsStream = _geo
            .collection(collectionRef: eventsRef)
            .within(
              center: center,
              radius: 10, // bán kính 10km
              field: 'position',
              strictMode: true,
            );
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ... (Các hàm _formatTimeAgo, _formatEventTime, _getSportVisual giữ nguyên) ...
  String _formatTimeAgo(Timestamp? timestamp) {
    if (timestamp == null) {
      return '';
    }
    final now = DateTime.now();
    final dateTime = timestamp.toDate();
    final difference = now.difference(dateTime);
    if (difference.inSeconds < 60) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }

  String _formatEventTime(Timestamp? timestamp) {
    if (timestamp == null) {
      return '';
    }
    final dateTime = timestamp.toDate();
    final formatter = DateFormat('h:mm a - MMM d');
    return formatter.format(dateTime);
  }

  String _getSportVisual(String? sportName) {
    switch (sportName) {
      case 'Bóng đá':
        return '⚽️';
      case 'Bóng chuyền':
        return '🏐';
      case 'Bóng rổ':
        return '🏀';
      case 'Bóng bàn':
        return '🏓';
      case 'Cầu lông':
        return '🏸';
      case 'Tennis':
        return '🎾';
      default:
        return '🏆';
    }
  }

  // ... (Hàm _getControlledOrganizerIds, _deleteEvent, _editEvent, _navigateToAllEvents giữ nguyên) ...
  Future<List<String>> _getControlledOrganizerIds(String uid) async {
    List<String> controlledIds = [uid];
    final teamsQuery = await _firestore
        .collection('teams')
        .where('ownerId', isEqualTo: uid)
        .get();
    for (final teamDoc in teamsQuery.docs) {
      controlledIds.add(teamDoc.id);
    }
    return controlledIds;
  }

  Future<void> _deleteEvent(DocumentSnapshot eventDoc) async {
    bool delete =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Confirm Deletion'),
            content: const Text('Are you sure...?'),
            actions: [
              // <-- 'actions' giờ đã nằm trong AlertDialog
              TextButton(
                child: const Text('Cancel'),
                onPressed: () =>
                    Navigator.of(ctx).pop(false), // <-- 'ctx' ở đây đã hợp lệ
              ),
              TextButton(
                child: const Text('Delete'),
                onPressed: () => Navigator.of(ctx).pop(true),
              ),
            ],
          ), // <-- Dấu ) này đóng AlertDialog ở đây
        ) ??
        false;

    if (!delete) {
      return;
    }

    // --- START: SỬA LOGIC XÓA ---
    try {
      String eventId = eventDoc.id; // ID của sự kiện (Event)
      Map<String, dynamic> data = eventDoc.data() as Map<String, dynamic>;
      String? imageUrl = data['imageUrl'];

      // 1. Khởi tạo một WriteBatch
      final batch = _firestore.batch();

      // 2. Tìm tất cả joinRequests liên quan đến sự kiện này
      final requestsQuery = await _firestore
          .collection('joinRequests')
          .where('eventId', isEqualTo: eventId)
          .get();

      // 3. Cập nhật status của các request đó thành 'cancelled'
      for (final requestDoc in requestsQuery.docs) {
        // Chỉ cập nhật nếu status chưa phải là cancelled (để tiết kiệm)
        if (requestDoc.data()['status'] != 'cancelled') {
          batch.update(requestDoc.reference, {'status': 'cancelled'});
        }
      }

      // 4. Thêm lệnh xóa sự kiện (Event) vào batch
      batch.delete(_firestore.collection('events').doc(eventId));

      // 5. Thực thi tất cả các lệnh (update + delete) cùng lúc
      await batch.commit();

      // 6. Xóa ảnh (sau khi batch thành công)
      if (imageUrl != null && imageUrl.isNotEmpty) {
        await FirebaseStorage.instance.refFromURL(imageUrl).delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Event deleted and all requests have been cancelled.',
            ),
            backgroundColor: Colors.green, // Báo thành công
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete event: $e')));
      }
    }
    // --- END: SỬA LOGIC XÓA ---
  }

  void _navigateToAllEvents(List<DocumentSnapshot> events) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => AllEventsScreen(events: events)),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      backgroundColor: kWhiteColor,
      appBar: AppBar(
        backgroundColor: kWhiteColor,
        elevation: 0,
        title: const Text(
          'Discover',
          style: TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
            fontSize: 28,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: kBlackColor),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateEventScreen(),
                ),
              );
            },
          ),
          // --- XÓA NÚT SEARCH ---
          // IconButton(
          //   icon: const Icon(Icons.search, color: kBlackColor),
          //   onPressed: _showFilterDialog,
          // ),
          // --- KẾT THÚC XÓA ---
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            alignment: Alignment.centerLeft,
            child: TabBar(
              controller: _tabController,
              indicatorColor: kAccentColor,
              labelColor: Colors.black,
              unselectedLabelColor: Colors.black54,
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 17,
              ),
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'History'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDiscoverTab(context), _buildHistoryTab()],
      ),
    );
  }

  Widget _buildDiscoverTab(BuildContext context) {
    return FutureBuilder(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Error: ${snapshot.error}"),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _initFuture = _getCurrentLocationAndSetupStream();
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            await _getCurrentLocationAndSetupStream();
            setState(() {});
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _buildEventsSection(),
              const SizedBox(height: 18),
              _buildSectionHeader(
                'Partners Near You',
                'Find a partner for your next game',
                onViewAll: () {
                  if (_currentPosition == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đang lấy vị trí, vui lòng thử lại...'),
                      ),
                    );
                    return;
                  }
                  // --- THAY ĐỔI: Chỉ truyền vị trí ---
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          AllPartnersScreen(currentPosition: _currentPosition!),
                    ),
                  );
                  // --- KẾT THÚC THAY ĐỔI ---
                },
              ),
              // Hiển thị bản đồ
              _buildPartnersList(),
            ],
          ),
        );
      },
    );
  }

  // ... (Hàm _buildHistoryTab giữ nguyên) ...
  Widget _buildHistoryTab() {
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      return const Center(
        child: Text('Please log in to see your event history.'),
      );
    }

    return FutureBuilder<List<String>>(
      future: _getControlledOrganizerIds(currentUser.uid),
      builder: (context, idListSnapshot) {
        if (idListSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (idListSnapshot.hasError) {
          return Center(
            child: Text('Error fetching teams: ${idListSnapshot.error}'),
          );
        }

        final controlledIds = idListSnapshot.data;
        if (controlledIds == null || controlledIds.isEmpty) {
          return const Center(
            child: Text('You have not created any events yet.'),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('events')
              .where('organizerId', whereIn: controlledIds)
              .orderBy('createdAt', descending: true)
              .snapshots(),
          builder: (context, eventSnapshot) {
            if (eventSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (eventSnapshot.hasError) {
              return Center(child: Text('Error: ${eventSnapshot.error}'));
            }
            if (!eventSnapshot.hasData || eventSnapshot.data!.docs.isEmpty) {
              return const Center(
                child: Text('You have not created any events yet.'),
              );
            }

            var eventDocs = eventSnapshot.data!.docs;

            return ListView.builder(
              itemCount: eventDocs.length,
              itemBuilder: (context, index) {
                DocumentSnapshot doc = eventDocs[index];
                Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

                String imageUrl = data['imageUrl'] ?? '';
                String eventName = data['eventName'] ?? 'No Name';
                String locationName = data['locationName'] ?? 'No Location';
                String creatorType = data['creatorType'] ?? 'individual';

                IconData creatorIcon = (creatorType == 'team')
                    ? Icons.group
                    : Icons.person;
                Color creatorColor = (creatorType == 'team')
                    ? Colors.blue.shade700
                    : Colors.green.shade700;

                Widget leadingWidget = SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              Container(color: Colors.grey[200]),
                          errorWidget: (context, url, error) =>
                              const Icon(Icons.error),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            creatorIcon,
                            color: creatorColor,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  child: ListTile(
                    leading: leadingWidget,
                    title: Text(eventName),
                    subtitle: Text(locationName),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteEvent(doc),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ... (Hàm _buildEventsSection, _buildTrendingEventCard, _buildSectionHeader giữ nguyên) ...
  Widget _buildEventsSection() {
    if (_eventsStream == null) {
      return Container(
        height: 320,
        alignment: Alignment.center,
        child: const Text('Could not load events. Try refreshing.'),
      );
    }
    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _eventsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 320,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Container(
            height: 320,
            alignment: Alignment.center,
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final allEvents = snapshot.data ?? [];
        final now = DateTime.now();
        final futureEvents = allEvents.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final bool isFull = data['isFull'] ?? false;
          if (isFull) {
            return false;
          }
          final eventTime = data['eventTime'] as Timestamp?;
          if (eventTime == null) return false;
          return eventTime.toDate().isAfter(now);
        }).toList();

        if (futureEvents.isEmpty) {
          return Column(
            children: [
              _buildSectionHeader(
                'Events near you',
                'Join and cheer with community',
                onViewAll: () {},
              ),
              Container(
                height: 250,
                alignment: Alignment.center,
                child: const Text('No upcoming events found near you.'),
              ),
            ],
          );
        }

        int eventCount = futureEvents.length;

        return Column(
          children: [
            _buildSectionHeader(
              'Events near you',
              'Join and cheer with community',
              onViewAll: () => _navigateToAllEvents(futureEvents),
            ),
            CarouselSlider.builder(
              carouselController: _eventCarouselController,
              itemCount: eventCount,
              itemBuilder: (context, index, realIndex) {
                final eventDoc = futureEvents[index];
                Map<String, dynamic> eventData =
                    eventDoc.data() as Map<String, dynamic>;
                String eventName = eventData['eventName'] ?? 'No Name';
                String locationName =
                    eventData['locationName'] ?? 'No Location';
                String imageUrl =
                    eventData['imageUrl'] ??
                    'https://via.placeholder.com/300x180.png?text=Event';
                Timestamp? createdAt = eventData['createdAt'];
                Timestamp? eventTime = eventData['eventTime'];
                String? sport = eventData['sport'];

                return _buildTrendingEventCard(
                  eventDoc,
                  imageUrl,
                  eventName,
                  locationName,
                  createdAt,
                  eventTime,
                  sport,
                );
              },
              options: CarouselOptions(
                height: 250.0,
                aspectRatio: 16 / 9,
                autoPlay: eventCount > 1,
                enlargeCenterPage: eventCount > 1,
                viewportFraction: eventCount > 1 ? 0.85 : 1.0,
                scrollPhysics: eventCount > 1
                    ? const AlwaysScrollableScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                autoPlayInterval: const Duration(seconds: 5),
                autoPlayAnimationDuration: const Duration(milliseconds: 800),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrendingEventCard(
    DocumentSnapshot eventDoc,
    String imageUrl,
    String title,
    String subtitle,
    Timestamp? createdAt,
    Timestamp? eventTime,
    String? sport,
  ) {
    final String timeAgo = _formatTimeAgo(createdAt);
    final data = eventDoc.data() as Map<String, dynamic>;
    final Timestamp? eventEndTime = data['eventEndTime'];

    // Format thời gian hiển thị (bắt đầu - kết thúc)
    String formattedEventTime;
    if (eventTime != null && eventEndTime != null) {
      final startTime = DateFormat('h:mm a').format(eventTime.toDate());
      final endTime = DateFormat('h:mm a').format(eventEndTime.toDate());
      final date = DateFormat('MMM d').format(eventTime.toDate());
      formattedEventTime = '$startTime - $endTime, $date';
    } else if (eventTime != null) {
      formattedEventTime = _formatEventTime(eventTime);
    } else {
      formattedEventTime = 'TBA';
    }

    final String sportVisual = _getSportVisual(sport);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EventDetailScreen(eventDoc: eventDoc),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        child: Card(
          elevation: 2.0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: kDefaultBorderRadius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[200]),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
              ListTile(
                isThreeLine: true,
                leading: CircleAvatar(
                  backgroundColor: kAccentColor.withOpacity(0.2),
                  child: Text(
                    sportVisual,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13),
                    ),
                    Text(
                      formattedEventTime,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
                trailing: Text(
                  timeAgo,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    String subtitle, {
    CarouselSliderController? controller,
    VoidCallback? onViewAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        kDefaultPadding,
        kDefaultPadding,
        kDefaultPadding,
        0,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ],
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              child: const Text(
                'View All',
                style: TextStyle(color: kAccentColor),
              ),
            )
          else if (controller != null)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => controller.previousPage(),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => controller.nextPage(),
                ),
              ],
            )
          else
            TextButton(
              onPressed: () {},
              child: const Text(
                'View All',
                style: TextStyle(color: kAccentColor),
              ),
            ),
        ],
      ),
    );
  }

  // --- XÓA HÀM LỌC ---
  // void _showFilterDialog() { ... }
  // --- KẾT THÚC XÓA ---

  // --- START: THÊM HELPER CHO BẢN ĐỒ ---
  Widget _buildUserLocationMarker() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.withAlpha(51),
        border: Border.all(color: Colors.blue.shade700, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withAlpha(77),
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.person_pin_circle,
          color: Colors.blue.shade800,
          size: 24,
        ),
      ),
    );
  }

  Marker _buildPartnerMapMarker(
    String userId,
    Map<String, dynamic> userData,
    GeoPoint geoPoint,
  ) {
    final String name = userData['displayName'] ?? 'Sporty User';
    final String photoUrl = userData['photoURL'] ?? 'https-invalid-url';

    return Marker(
      point: LatLng(geoPoint.latitude, geoPoint.longitude),
      width: 80,
      height: 100,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfileScreen(userId: userId),
            ),
          );
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: kAccentColor, width: 2),
                color: Colors.white,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: CachedNetworkImage(
                  imageUrl: photoUrl,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  placeholder: (context, url) =>
                      Container(color: Colors.grey[200]),
                  errorWidget: (context, url, error) =>
                      const Icon(Icons.person, size: 40, color: Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.black,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
  // --- END: THÊM HELPER CHO BẢN ĐỒ ---

  // --- START: CẬP NHẬT HÀM NÀY ĐỂ BỎ LỌC ---
  Widget _buildPartnersList() {
    if (_partnersStream == null || _currentPosition == null) {
      return Container(
        height: 250,
        alignment: Alignment.center,
        child: const Text('Đang tải bản đồ bạn tập...'),
      );
    }

    return StreamBuilder<List<DocumentSnapshot>>(
      stream: _partnersStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 250,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return Container(
            height: 250,
            alignment: Alignment.center,
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final allPartners = snapshot.data ?? [];

        // --- THAY ĐỔI: Chỉ lọc user hiện tại ---
        final filteredPartners = allPartners.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null) return false;
          // Chỉ lọc chính mình
          if (doc.id == _auth.currentUser?.uid) return false;
          return true;
        }).toList();
        // --- KẾT THÚC THAY ĐỔI ---

        List<Marker> markers = [];
        markers.add(
          Marker(
            point: LatLng(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
            ),
            width: 40,
            height: 40,
            child: _buildUserLocationMarker(),
          ),
        );

        for (final doc in filteredPartners) {
          final data = doc.data() as Map<String, dynamic>;
          final geoPoint = data['position']?['geopoint'] as GeoPoint?;

          if (geoPoint != null) {
            markers.add(_buildPartnerMapMarker(doc.id, data, geoPoint));
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SizedBox(
            height: 250,
            child: ClipRRect(
              borderRadius: kDefaultBorderRadius,
              child: FlutterMap(
                mapController: MapController(),
                options: MapOptions(
                  initialCenter: LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  ),
                  initialZoom: 12.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://maps.vietmap.vn/api/tm/{z}/{x}/{y}.png?apikey=$vietmapApiKey',
                    userAgentPackageName:
                        'com.example.sportconnect', // TODO: Thay bằng tên package của bạn
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- END: CẬP NHẬT HÀM ---
}
