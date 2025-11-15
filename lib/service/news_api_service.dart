import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../models/news_item.dart';

class NewsApiService {
  //static const String apiUrl = "http://10.0.2.2:5001/api/sports-news";
  static const String apiUrl =
      "https://sports-news-api-ibbmx7acda-as.a.run.app/api/sports-news";
  Future<List<NewsItem>> fetchNews() async {
    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        return data.map((json) => NewsItem.fromJson(json)).toList();
      } else {
        throw Exception('Lỗi server: ${response.statusCode}');
      }
    } on TimeoutException catch (_) {
      throw Exception(
        'Hết thời gian chờ kết nối. Hãy đảm bảo API Python đang chạy.',
      );
    } catch (e) {
      throw Exception('Không thể kết nối đến API. Lỗi: $e');
    }
  }
}
