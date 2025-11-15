import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/field_item.dart';
import '../config/api_keys.dart';

class FieldDetailScreen extends StatefulWidget {
  final FieldItem field;
  final Position currentPosition;

  const FieldDetailScreen({
    super.key,
    required this.field,
    required this.currentPosition,
  });

  @override
  State<FieldDetailScreen> createState() => _FieldDetailScreenState();
}

class _FieldDetailScreenState extends State<FieldDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  final MapController _mapController = MapController();
  List<LatLng> _routePoints = [];
  late String _fullAddress;
  bool _isExpanded = false;
  late AnimationController _animationController;
  late Animation<double> animation;
  String _distance = '';
  String _duration = '';
  List<Map<String, dynamic>> _instructions =
      []; // Thêm hướng dẫn chi tiết (enriched)

  @override
  void initState() {
    super.initState();
    _fullAddress = widget.field.address ?? 'Không tìm thấy địa chỉ.';
    _loadInitialData();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      await _fetchRoute();
    } catch (e) {
      // Lỗi khi tải dữ liệu ban đầu
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tải dữ liệu: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Cập nhật hàm _fetchRoute để lấy route chi tiết hơn
  Future<void> _fetchRoute() async {
    final startLat = widget.currentPosition.latitude;
    final startLon = widget.currentPosition.longitude;
    final endLat = widget.field.latitude;
    final endLon = widget.field.longitude;

    // Thêm các tham số để lấy route chi tiết hơn
    final url = Uri.parse(
      'https://maps.vietmap.vn/api/route?apikey=$vietmapApiKey&point=$startLat,$startLon&point=$endLat,$endLon&vehicle=car&points_encoded=false&instructions=true&alternatives=false',
    );

    try {
      // Calling Vietmap API
      final response = await http.get(url);

      // Response status and body for debugging
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));

        if (data['paths'] != null && (data['paths'] as List).isNotEmpty) {
          final path = data['paths'][0];

          // Lấy thông tin khoảng cách và thời gian
          if (path['distance'] != null) {
            final distanceMeters = path['distance'] as num;
            _distance = '${(distanceMeters / 1000).toStringAsFixed(1)} km';
          }

          if (path['time'] != null) {
            final timeMillis = path['time'] as num;
            final minutes = (timeMillis / 60000).round();
            _duration = '$minutes phút';
          }

          // Lấy tọa độ đường đi chi tiết hơn
          if (path['points'] != null && path['points']['coordinates'] != null) {
            final coordinates = path['points']['coordinates'] as List;
            _routePoints = coordinates
                .map<LatLng>((coord) => LatLng(coord[1], coord[0]))
                .toList();

            // Route points loaded

            // Tự động căn chỉnh bản đồ với padding lớn hơn
            if (mounted && _routePoints.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(_routePoints),
                    padding: const EdgeInsets.all(60.0), // Tăng padding
                  ),
                );
              });
            }
          }
        } else {
          // Vietmap không tìm thấy đường đi
        }
      } else {
        throw Exception(
          'Lỗi API Vietmap: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      // Lỗi khi kết nối đến Vietmap Direction API
      // Không throw exception để app vẫn hiển thị bản đồ
    }
  }

  Future<void> _launchInGoogleMaps() async {
    final lat = widget.field.latitude;
    final lon = widget.field.longitude;
    final url = Uri.parse('google.navigation:q=$lat,$lon');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      final fallbackUrl = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
      );
      if (await canLaunchUrl(fallbackUrl)) {
        await launchUrl(fallbackUrl, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Không thể mở Google Maps. Vui lòng kiểm tra lại.'),
            ),
          );
        }
      }
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
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

  @override
  Widget build(BuildContext context) {
    final sportColor = _getSportColor(widget.field.sportType);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          widget.field.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(26),
                blurRadius: 8,
              ), // 0.1 * 255
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Bản đồ sử dụng Vietmap raster tiles
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(
                widget.field.latitude,
                widget.field.longitude,
              ),
              initialZoom: 15.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                // Sử dụng raster tiles thay vì styles.json
                urlTemplate:
                    'https://maps.vietmap.vn/api/tm/{z}/{x}/{y}.png?apikey=$vietmapApiKey',
                userAgentPackageName: 'com.example.sport_connect_app',
                additionalOptions: const {'apikey': vietmapApiKey},
              ),
              // Hiển thị route với gradient và shadow
              if (_routePoints.isNotEmpty) ...[
                // Shadow cho route
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 8,
                      color: Colors.black.withAlpha(77), // 0.3 * 255
                    ),
                  ],
                ),
                // Route chính với gradient
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5,
                      color: sportColor,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
              ],
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(
                      widget.currentPosition.latitude,
                      widget.currentPosition.longitude,
                    ),
                    width: 40,
                    height: 40,
                    child: _buildUserLocationMarker(),
                  ),
                  Marker(
                    point: LatLng(
                      widget.field.latitude,
                      widget.field.longitude,
                    ),
                    width: 50,
                    height: 50,
                    child: _buildDestinationMarker(sportColor),
                  ),
                ],
              ),
            ],
          ),

          // Panel thông tin có thể thu gọn/mở rộng
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta! < -10) {
                  if (!_isExpanded) _toggleExpanded();
                } else if (details.primaryDelta! > 10) {
                  if (_isExpanded) _toggleExpanded();
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                height: _isExpanded
                    ? MediaQuery.of(context).size.height * 0.7
                    : 220,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(51), // 0.2 * 255
                      blurRadius: 20,
                      offset: const Offset(0, -5),
                    ),
                  ],
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                        children: [
                          // Handle bar
                          GestureDetector(
                            onTap: _toggleExpanded,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade300,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Icon(
                                    _isExpanded
                                        ? Icons.keyboard_arrow_down
                                        : Icons.keyboard_arrow_up,
                                    color: Colors.grey.shade600,
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Nội dung
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header với icon sport
                                  Row(
                                    children: [
                                      Container(
                                        width: 60,
                                        height: 60,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              sportColor.withAlpha(
                                                204,
                                              ), // 0.8 * 255
                                              sportColor,
                                            ],
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: sportColor.withAlpha(
                                                77,
                                              ), // 0.3 * 255
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Center(
                                          child: Text(
                                            _getSportVisual(
                                              widget.field.sportType,
                                            ),
                                            style: const TextStyle(
                                              fontSize: 32,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              widget.field.name,
                                              style: const TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: sportColor.withAlpha(
                                                  26,
                                                ), // 0.1 * 255
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                widget.field.sportType,
                                                style: TextStyle(
                                                  fontSize: 14,
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
                                  const SizedBox(height: 24),

                                  // Quick info
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: sportColor.withAlpha(
                                        13,
                                      ), // 0.05 * 255
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            children: [
                                              Icon(
                                                Icons.social_distance,
                                                color: sportColor,
                                                size: 28,
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                _distance.isNotEmpty
                                                    ? _distance
                                                    : '${widget.field.distanceKm.toStringAsFixed(1)} km',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: sportColor,
                                                ),
                                              ),
                                              const Text(
                                                'Khoảng cách',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (_duration.isNotEmpty)
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Icon(
                                                  Icons.access_time,
                                                  color: sportColor,
                                                  size: 28,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  _duration,
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: sportColor,
                                                  ),
                                                ),
                                                const Text(
                                                  'Thời gian',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                  if (_isExpanded) ...[
                                    const SizedBox(height: 24),
                                    const Divider(),
                                    const SizedBox(height: 16),
                                    _buildDetailRow(
                                      Icons.location_on_outlined,
                                      'Địa chỉ',
                                      _fullAddress,
                                      sportColor,
                                    ),
                                    const SizedBox(height: 16),
                                    _buildDetailRow(
                                      Icons.map_outlined,
                                      'Tọa độ',
                                      '${widget.field.latitude.toStringAsFixed(6)}, ${widget.field.longitude.toStringAsFixed(6)}',
                                      sportColor,
                                    ),
                                    // Hiển thị hướng dẫn chi tiết nếu có
                                    if (_instructions.isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      _buildDetailRow(
                                        Icons.directions,
                                        'Hướng dẫn',
                                        '${_instructions.length} bước',
                                        sportColor,
                                      ),
                                      const SizedBox(height: 12),
                                      _buildInstructionsList(sportColor),
                                    ],
                                    const SizedBox(height: 24),
                                  ],

                                  // Button điều hướng
                                  Container(
                                    width: double.infinity,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          sportColor.withAlpha(
                                            204,
                                          ), // 0.8 * 255
                                          sportColor,
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: sportColor.withAlpha(
                                            77,
                                          ), // 0.3 * 255
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: _launchInGoogleMaps,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        foregroundColor: Colors.white,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.navigation,
                                        size: 24,
                                      ),
                                      label: const Text(
                                        'Chỉ đường đến đây',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsList(Color color) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(8),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _instructions.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final step = _instructions[index];
          final text = step['text'] as String? ?? '';
          final dist = step['distance'] as double?;
          final time = step['time'] as int?;
          final latLng = step['latLng'] as LatLng?;

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 6,
            ),
            leading: CircleAvatar(
              backgroundColor: color.withAlpha(51),
              child: Text(
                '${index + 1}',
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(text, style: const TextStyle(fontSize: 14)),
            subtitle: (dist != null || time != null)
                ? Text(
                    '${dist != null ? (dist / 1000).toStringAsFixed(2) + ' km' : ''}${(dist != null && time != null) ? ' • ' : ''}${time != null ? (time ~/ 60).toString() + ' min' : ''}',
                    style: const TextStyle(fontSize: 12),
                  )
                : null,
            trailing: latLng != null
                ? Icon(Icons.my_location, color: color)
                : const Icon(Icons.chevron_right),
            onTap: () {
              if (latLng != null) {
                _centerMapOnStep(latLng);
              } else if (_routePoints.isNotEmpty) {
                // fallback: center on a nearby route point
                final fallback =
                    _routePoints[(index * 3).clamp(0, _routePoints.length - 1)];
                _centerMapOnStep(fallback);
              }
            },
          );
        },
      ),
    );
  }

  void _centerMapOnStep(LatLng latLng) {
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([
            latLng,
            LatLng(
              widget.currentPosition.latitude,
              widget.currentPosition.longitude,
            ),
          ]),
          padding: const EdgeInsets.all(60),
        ),
      );
    } catch (e) {
      // fallback: move to point with zoom
      _mapController.move(latLng, 17);
    }
  }

  Widget _buildUserLocationMarker() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.withAlpha(51), // 0.2 * 255
        border: Border.all(color: Colors.blue.shade700, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withAlpha(77), // 0.3 * 255
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

  Widget _buildDestinationMarker(Color color) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(77), // 0.3 * 255
            spreadRadius: 2,
            blurRadius: 8,
          ),
        ],
      ),
      child: Center(child: Icon(Icons.location_on, color: color, size: 40)),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(26), // 0.1 * 255
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
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
