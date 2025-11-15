import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'event_detail_screen.dart'; // Đảm bảo bạn đã import màn hình chi tiết

// Định nghĩa lại các hằng số nếu file constants của bạn chưa có hoặc để tiện sử dụng
const Color kPrimaryColor = Color.fromRGBO(7, 7, 112, 1);
const Color kAccentColor = Colors.blue;
const Color kWhiteColor = Colors.white;
const double kDefaultPadding = 16.0;
final BorderRadius kDefaultBorderRadius = BorderRadius.circular(12.0);

class EventOfTeamScreen extends StatelessWidget {
  final String teamId;
  final String teamName;

  const EventOfTeamScreen({
    Key? key,
    required this.teamId,
    required this.teamName,
  }) : super(key: key);

  // --- CÁC HÀM HELPER (Copy từ all_events_screen.dart) ---

  String _formatEventTime(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dateTime = timestamp.toDate();
    final formatter = DateFormat('h:mm a - MMM d');
    return formatter.format(dateTime);
  }

  String _formatEventTimeRange(Timestamp? startTime, Timestamp? endTime) {
    if (startTime == null) return 'TBA';

    if (endTime != null) {
      final start = DateFormat('h:mm a').format(startTime.toDate());
      final end = DateFormat('h:mm a').format(endTime.toDate());
      final date = DateFormat('MMM d').format(startTime.toDate());
      return '$start - $end, $date';
    }

    return _formatEventTime(startTime);
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
  // --------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kWhiteColor, // Nền trắng giống AllEventsScreen
      appBar: AppBar(
        title: Text(
          'Sự kiện của $teamName',
          style: const TextStyle(
            color: kPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: kWhiteColor, // AppBar trắng
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: kPrimaryColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('events')
            .where('organizerId', isEqualTo: teamId)
            .where('creatorType', isEqualTo: 'team')
            .orderBy('eventTime', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Đã xảy ra lỗi: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_busy, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Đội này chưa có sự kiện nào.',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final events = snapshot.data!.docs;

          return ListView.builder(
            // Padding giống AllEventsScreen nhưng thêm chút ở bottom để không bị sát quá
            padding: const EdgeInsets.only(bottom: kDefaultPadding),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final eventDoc = events[index];
              final data = eventDoc.data() as Map<String, dynamic>;

              // Lấy dữ liệu skillLevel giống AllEventsScreen
              final skillLevel = data['skillLevel'] ?? 'N/A';

              return Card(
                margin: const EdgeInsets.symmetric(
                  horizontal: kDefaultPadding,
                  vertical: 8,
                ),
                elevation: 2.0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: kDefaultBorderRadius,
                ),
                child: InkWell(
                  onTap: () {
                    // Điều hướng sang trang chi tiết
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            EventDetailScreen(eventDoc: eventDoc),
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Ảnh cover
                      CachedNetworkImage(
                        imageUrl: data['imageUrl'] ?? '',
                        height: 150,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          height: 150,
                          color: Colors.grey[200],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          height: 150,
                          color: Colors.grey[200],
                          child: const Icon(Icons.error),
                        ),
                      ),

                      // 2. Thông tin chi tiết dùng ListTile
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kAccentColor.withOpacity(0.2),
                          child: Text(_getSportVisual(data['sport'])),
                        ),
                        title: Text(
                          data['eventName'] ?? 'No Title',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${data['locationName'] ?? 'No Location'}\n${_formatEventTimeRange(data['eventTime'], data['eventEndTime'])}',
                        ),
                        isThreeLine: true,
                        trailing: Chip(
                          label: Text(
                            skillLevel,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                              fontSize: 12,
                            ),
                          ),
                          backgroundColor: Colors.blue[50],
                          avatar: Icon(
                            Icons.leaderboard_outlined,
                            color: Colors.blue[800],
                            size: 16,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
