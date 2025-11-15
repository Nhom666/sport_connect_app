class FieldItem {
  final String name;
  final double latitude;
  final double longitude;
  final String sportType;
  final double distanceKm;
  final String? address;

  FieldItem({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.sportType,
    required this.distanceKm,
    this.address,
  });
}
