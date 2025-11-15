import 'dart:convert';
import 'dart:typed_data';

class NewsItem {
  final String title;
  final String link;
  final String imageUrl;
  final String description;
  final String source;

  NewsItem({
    required this.title,
    required this.link,
    required this.imageUrl,
    required this.description,
    required this.source,
  });

  factory NewsItem.fromJson(Map<String, dynamic> json) {
    // Xử lý imageUrl với nhiều fallback options
    String imageUrl = '';

    // Thử các trường có thể chứa URL ảnh
    if (json['image'] != null && json['image'].toString().isNotEmpty) {
      imageUrl = json['image'].toString();
    } else if (json['thumbnail'] != null &&
        json['thumbnail'].toString().isNotEmpty) {
      imageUrl = json['thumbnail'].toString();
    } else if (json['urlToImage'] != null &&
        json['urlToImage'].toString().isNotEmpty) {
      imageUrl = json['urlToImage'].toString();
    } else if (json['imageUrl'] != null &&
        json['imageUrl'].toString().isNotEmpty) {
      imageUrl = json['imageUrl'].toString();
    } else if (json['enclosure'] != null && json['enclosure']['link'] != null) {
      imageUrl = json['enclosure']['link'].toString();
    }

    // Validate URL (phải bắt đầu bằng http://, https:// hoặc data:)
    if (imageUrl.isNotEmpty &&
        !imageUrl.startsWith('http') &&
        !imageUrl.startsWith('data:')) {
      imageUrl = '';
    }

    return NewsItem(
      title: json['title']?.toString() ?? 'Không có tiêu đề',
      link: json['link']?.toString() ?? '',
      imageUrl: imageUrl,
      description: json['description']?.toString() ?? '',
      source: json['source']?.toString() ?? 'Không rõ nguồn',
    );
  }

  // Thêm method để check có ảnh hợp lệ không
  bool get hasValidImage =>
      imageUrl.isNotEmpty &&
      (imageUrl.startsWith('http://') ||
          imageUrl.startsWith('https://') ||
          imageUrl.startsWith('data:'));

  // Method để check xem có phải data URL không
  bool get isDataUrl => imageUrl.startsWith('data:');

  // Method để decode data URL thành Uint8List với tối ưu hóa
  Uint8List? getDataUrlBytes() {
    if (!isDataUrl) return null;

    try {
      // Manually parse data URL instead of using Uri.parse()
      // Format: data:[<mediatype>][;base64],<data>
      final commaIndex = imageUrl.indexOf(',');
      if (commaIndex == -1 || commaIndex >= imageUrl.length - 1) {
        print('Invalid data URL format: $imageUrl');
        return null;
      }

      final header = imageUrl.substring(0, commaIndex);
      final data = imageUrl.substring(commaIndex + 1);

      // Check if it's base64 encoded
      final isBase64 = header.contains(';base64');

      if (isBase64) {
        // Loại bỏ whitespace và validate base64 format
        final cleanBase64 = data.trim();
        if (cleanBase64.isEmpty) {
          print('Base64 content is empty');
          return null;
        }

        // Check for invalid base64 characters
        bool hasInvalidChars = false;
        for (int i = 0; i < cleanBase64.length; i++) {
          final char = cleanBase64.codeUnitAt(i);
          if (char > 127 ||
              (char != 43 &&
                  char != 47 &&
                  char != 61 &&
                  !(char >= 48 && char <= 57) &&
                  !(char >= 65 && char <= 90) &&
                  !(char >= 97 && char <= 122))) {
            print(
              'Found invalid base64 character at position $i: ${cleanBase64[i]} (ASCII: $char)',
            );
            hasInvalidChars = true;
          }
        }
        if (hasInvalidChars) {
          print('Skipping data URL due to invalid base64 characters');
          return null;
        }

        // Kiểm tra base64 format cơ bản (chỉ cho phép A-Z, a-z, 0-9, +, /, =)
        final base64Regex = RegExp(r'^[A-Za-z0-9+/]*={0,2}$');
        if (!base64Regex.hasMatch(cleanBase64)) {
          print('Invalid base64 format: $cleanBase64');
          return null;
        }

        // Thêm padding nếu cần (base64 cần length chia hết cho 4)
        final paddedBase64 = _addBase64Padding(cleanBase64);

        try {
          return base64Decode(paddedBase64);
        } catch (base64Error) {
          print('Base64 decode error: $base64Error for content: $paddedBase64');
          // If base64 decoding fails, try to handle common issues
          if (base64Error.toString().contains('Invalid value in input')) {
            print('Detected invalid base64 character, skipping this data URL');
          }
          return null;
        }
      } else {
        // Nếu không phải base64, trả về bytes từ string
        return Uint8List.fromList(data.codeUnits);
      }
    } catch (e) {
      print('Error decoding data URL: $e for URL: $imageUrl');
      return null;
    }
  }

  // Helper method để thêm padding cho base64 string
  String _addBase64Padding(String base64String) {
    final length = base64String.length;
    final remainder = length % 4;

    if (remainder == 0) {
      return base64String;
    } else if (remainder == 2) {
      return base64String + '==';
    } else if (remainder == 3) {
      return base64String + '=';
    } else {
      // remainder == 1 - invalid base64, nhưng chúng ta đã validate ở trên
      return base64String;
    }
  }

  // Test method để verify data URL decoding
  static void testDataUrlDecoding() {
    // Test với data URL mẫu
    const testDataUrl =
        'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==';

    final testItem = NewsItem(
      title: 'Test',
      link: '',
      imageUrl: testDataUrl,
      description: '',
      source: '',
    );

    print('Testing data URL: $testDataUrl');
    print('Is data URL: ${testItem.isDataUrl}');
    print('Has valid image: ${testItem.hasValidImage}');

    final bytes = testItem.getDataUrlBytes();
    print('Decoded bytes length: ${bytes?.length ?? 0}');
    if (bytes != null && bytes.isNotEmpty) {
      print('First 10 bytes: ${bytes.take(10).toList()}');
      print('Successfully decoded data URL!');
    } else {
      print('Failed to decode data URL');
    }
  }
}
