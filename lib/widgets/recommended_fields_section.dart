import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../../config/api_keys.dart';
import '../../models/field_item.dart';
import '../screens/field_detail_screen.dart';

class RecommendedFieldsSection extends StatefulWidget {
  const RecommendedFieldsSection({super.key});

  @override
  State<RecommendedFieldsSection> createState() =>
      RecommendedFieldsSectionState();
}

class RecommendedFieldsSectionState extends State<RecommendedFieldsSection> {
  Position? _currentPosition;
  final List<FieldItem> _fields = [];
  bool _isLoading = true;
  String? _errorMessage;
  String _selectedSport = 'All';

  StreamSubscription<Position>? _positionStreamSubscription;

  final List<String> _supportedSports = const [
    'All',
    'Soccer',
    'Tennis',
    'Badminton',
    'Basketball',
    'Volleyball',
  ];

  @override
  void initState() {
    super.initState();
    _initializeLocationAndFetch();
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeLocationAndFetch() async {
    await _fetchRecommendedFieldsWithHere();
    _listenToPositionUpdates();
  }

  void _listenToPositionUpdates() {
    _positionStreamSubscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 100,
          ),
        ).listen((Position newPosition) async {
          if (!mounted || _currentPosition == null) return;

          final distance = Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            newPosition.latitude,
            newPosition.longitude,
          );

          if (distance > 500) {
            await _fetchRecommendedFieldsWithHere();
          }
        });
  }

  Future<void> refreshFields() async {
    await _fetchRecommendedFieldsWithHere();
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Dịch vụ vị trí (GPS) của điện thoại đang tắt.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Bạn đã từ chối quyền truy cập vị trí.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error(
        'Quyền vị trí đã bị từ chối vĩnh viễn. Vui lòng vào cài đặt của ứng dụng để cấp quyền.',
      );
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<String?> getAddressFromCoordinates(double lat, double lng) async {
    try {
      final reverseUri = Uri.https(
        'revgeocode.search.hereapi.com',
        '/v1/revgeocode',
        {'at': '$lat,$lng', 'lang': 'vi-VN', 'apiKey': hereApiKey},
      );
      final response = await http.get(reverseUri);
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final items = data['items'] as List?;
        if (items != null && items.isNotEmpty) {
          return items.first['address']?['label'] as String?;
        }
      }
    } catch (e) {
      print('DEBUG: Error in HERE reverse geocode: $e');
    }
    return null;
  }

  List<String> _getCategoryIds(List<dynamic> categories) {
    final tokens = <String>[];
    for (final category in categories) {
      if (category is Map<String, dynamic>) {
        final id = category['id'];
        if (id != null) tokens.add(id.toString());
      }
    }
    return tokens;
  }

  String _mapNameToAppSport(String placeName, List<dynamic> categories) {
    final lowerCaseName = placeName.toLowerCase();
    final catIds = _getCategoryIds(categories);

    // Loại trừ các từ khóa không phải thể thao mà ta hỗ trợ
    const excludeKeywords = [
      'golf',
      'gym',
      'fitness',
      'yoga',
      'bơi lội',
      'swimming',
      'bowling',
      'billiards',
      'bi-a',
      'club',
      'massage',
      'spa',
    ];

    // Kiểm tra xem có chứa từ khóa loại trừ không
    if (excludeKeywords.any((keyword) => lowerCaseName.contains(keyword))) {
      return 'Other';
    }

    // Kiểm tra theo tên tiếng Việt - ưu tiên cao nhất
    if (lowerCaseName.contains('bóng đá') ||
        lowerCaseName.contains('sân banh')) {
      return 'Soccer';
    }
    if (lowerCaseName.contains('bóng rổ')) {
      return 'Basketball';
    }
    if (lowerCaseName.contains('tennis') ||
        lowerCaseName.contains('quần vợt')) {
      return 'Tennis';
    }
    if (lowerCaseName.contains('cầu lông') ||
        lowerCaseName.contains('badminton')) {
      return 'Badminton';
    }
    if (lowerCaseName.contains('bóng chuyền') ||
        lowerCaseName.contains('volleyball')) {
      return 'Volleyball';
    }

    // Kiểm tra theo category ID của HERE API
    if (catIds.contains('800-8600-0183')) return 'Soccer';
    if (catIds.contains('800-8600-0192')) return 'Basketball';
    if (catIds.contains('800-8600-0189')) return 'Tennis';
    if (catIds.contains('800-8600-0180')) return 'Badminton';
    if (catIds.contains('800-8600-0197')) return 'Volleyball';

    // Chỉ gán Soccer nếu rõ ràng có từ "sân" + "bóng" hoặc "football"
    if ((lowerCaseName.contains('sân') && lowerCaseName.contains('bóng')) ||
        lowerCaseName.contains('football') ||
        lowerCaseName.contains('soccer')) {
      return 'Soccer';
    }

    // Nếu chỉ có "sân" hoặc "thể thao" mà không cụ thể -> loại bỏ
    return 'Other';
  }

  bool _isSportsRelated(String name, List<dynamic> categories) {
    final lowerName = name.toLowerCase();
    final catIds = _getCategoryIds(categories);

    // Loại trừ các môn thể thao không hỗ trợ
    const excludeKeywords = [
      'golf',
      'gym',
      'fitness',
      'yoga',
      'bơi lội',
      'swimming',
      'bowling',
      'billiards',
      'bi-a',
      'club',
      'massage',
      'spa',
      'karaoke',
    ];

    if (excludeKeywords.any((keyword) => lowerName.contains(keyword))) {
      return false;
    }

    // Kiểm tra category ID thể thao
    const sportCategoryPrefix = '800-8600';
    if (catIds.any((id) => id.startsWith(sportCategoryPrefix))) {
      // Nhưng loại trừ golf và các môn không hỗ trợ
      if (catIds.contains('800-8600-0175')) return false; // Golf
      if (catIds.contains('800-8600-0176')) return false; // Swimming
      return true;
    }

    // Kiểm tra từ khóa cụ thể cho các môn ta hỗ trợ
    const supportedKeywords = [
      'bóng đá',
      'sân banh',
      'football',
      'soccer',
      'bóng rổ',
      'basketball',
      'tennis',
      'quần vợt',
      'cầu lông',
      'badminton',
      'bóng chuyền',
      'volleyball',
    ];

    return supportedKeywords.any((keyword) => lowerName.contains(keyword));
  }

  Future<void> _fetchRecommendedFieldsWithHere() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final position = await _determinePosition();
      if (!mounted) return;

      setState(() {
        _currentPosition = position;
      });

      final lat = position.latitude;
      final lon = position.longitude;

      final browseUri = Uri.https('browse.search.hereapi.com', '/v1/browse', {
        'at': '$lat,$lon',
        'in': 'circle:$lat,$lon;r=5000',
        'limit': '50',
        'categories': '800-8600',
        'lang': 'vi-VN',
        'apiKey': hereApiKey,
      });

      final response = await http.get(browseUri);
      if (!mounted) return;

      if (response.statusCode != 200) {
        throw Exception('API Error: ${response.statusCode}');
      }

      final data = json.decode(utf8.decode(response.bodyBytes));
      final items = (data['items'] as List?) ?? [];
      final List<FieldItem> collected = [];
      final Set<String> addedIds = {};

      for (final rawItem in items) {
        if (rawItem is! Map<String, dynamic>) continue;

        final placeId = rawItem['id'] as String?;
        if (placeId == null || addedIds.contains(placeId)) continue;

        final positionData = rawItem['position'] as Map<String, dynamic>?;
        final itemLat = (positionData?['lat'] as num?)?.toDouble() ?? 0.0;
        final itemLon = (positionData?['lng'] as num?)?.toDouble() ?? 0.0;
        if (itemLat == 0.0) continue;

        final categoriesList = (rawItem['categories'] as List?) ?? [];
        final name = rawItem['title'] as String? ?? 'Không có tên';

        if (!_isSportsRelated(name, categoriesList)) continue;
        final sportType = _mapNameToAppSport(name, categoriesList);
        if (sportType == 'Other') continue;

        final distanceKm =
            Geolocator.distanceBetween(lat, lon, itemLat, itemLon) / 1000;
        if (distanceKm > 5.0) continue;

        final address = rawItem['address']?['label'] as String? ?? '';
        final field = FieldItem(
          name: name,
          latitude: itemLat,
          longitude: itemLon,
          sportType: sportType,
          distanceKm: distanceKm,
          address: address.isEmpty ? null : address,
        );
        addedIds.add(placeId);
        collected.add(field);
      }

      collected.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      setState(() {
        _fields.clear();
        _fields.addAll(collected.take(15));
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Colors.grey.shade50],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.location_on,
                    color: Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Fields Near You',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      Text(
                        'Khám phá các sân thể thao xung quanh',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildContent(),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading && _fields.isEmpty) {
      return Container(
        height: 240,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 16),
            const Text(
              'Đang tìm sân gần bạn...',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red.shade700, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Có lỗi xảy ra',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade700, fontSize: 13),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: refreshFields,
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final filteredFields = _selectedSport == 'All'
        ? _fields
        : _fields.where((f) => f.sportType == _selectedSport).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSportFilterChips(),
        const SizedBox(height: 16),
        _buildFieldsList(filteredFields),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFieldsList(List<FieldItem> filtered) {
    if (_fields.isEmpty && !_isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(
              Icons.sports_soccer_outlined,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'Không tìm thấy sân thể thao',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Không có sân nào trong bán kính 5km',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: refreshFields,
              icon: const Icon(Icons.refresh, size: 20),
              label: const Text('Tải lại'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (filtered.isEmpty && !_isLoading) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Không có sân $_selectedSport ở gần bạn',
                style: TextStyle(
                  color: Colors.orange.shade900,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 240, // Tăng từ 200 lên 240
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: filtered.length,
        itemBuilder: (context, index) => _buildFieldCard(filtered[index]),
      ),
    );
  }

  Widget _buildSportFilterChips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _supportedSports.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final sportName = _supportedSports[index];
          final bool selected = _selectedSport == sportName;
          return FilterChip(
            label: Text(sportName),
            selected: selected,
            onSelected: (bool newSelection) {
              if (newSelection) {
                setState(() => _selectedSport = sportName);
              }
            },
            selectedColor: Theme.of(context).primaryColor,
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            labelStyle: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: selected
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade300,
                width: selected ? 2 : 1,
              ),
            ),
            elevation: selected ? 2 : 0,
            shadowColor: Theme.of(context).primaryColor.withOpacity(0.3),
          );
        },
      ),
    );
  }

  Color _getSportColor(String sportType) {
    switch (sportType) {
      case 'Soccer':
        return Colors.green;
      case 'Basketball':
        return Colors.orange;
      case 'Badminton':
        return Colors.blue;
      case 'Tennis':
        return Colors.purple;
      case 'Volleyball':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getSportVisual(String sportType) {
    switch (sportType) {
      case 'Soccer':
        return '⚽️';
      case 'Basketball':
        return '🏀';
      case 'Badminton':
        return '🏸';
      case 'Tennis':
        return '🎾';
      case 'Volleyball':
        return '🏐';
      default:
        return '🏆';
    }
  }

  Widget _buildFieldCard(FieldItem field) {
    final visual = _getSportVisual(field.sportType);
    final sportColor = _getSportColor(field.sportType);
    final hasPosition = _currentPosition != null;

    return Container(
      width: 300,
      margin: const EdgeInsets.only(right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: sportColor.withOpacity(0.15),
            spreadRadius: 0,
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100, width: 1),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: hasPosition
              ? () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FieldDetailScreen(
                        field: field,
                        currentPosition: _currentPosition!,
                      ),
                    ),
                  );
                }
              : null,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min, // Thêm dòng này
              children: [
                // Header với icon và distance
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [sportColor.withOpacity(0.8), sportColor],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: sportColor.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          visual,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            field.sportType,
                            style: TextStyle(
                              fontSize: 13,
                              color: sportColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: sportColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${field.distanceKm.toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: sportColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12), // Giảm từ 16 xuống 12
                // Tên sân
                Text(
                  field.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16, // Giảm từ 17 xuống 16
                    color: Colors.black87,
                    height: 1.2, // Giảm từ 1.3 xuống 1.2
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                // Địa chỉ nếu có
                if (field.address != null)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          field.address!,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                // Button xem chi tiết
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [sportColor.withOpacity(0.8), sportColor],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: sportColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Xem chi tiết',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
