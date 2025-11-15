// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'dart:async';
// import '../../models/news_item.dart';
// import '../../config/api_keys.dart';

// class TrendingNewsSection extends StatefulWidget {
//   const TrendingNewsSection({super.key});

//   @override
//   State<TrendingNewsSection> createState() => TrendingNewsSectionState();
// }

// class TrendingNewsSectionState extends State<TrendingNewsSection> {
//   late Future<List<NewsItem>> _newsFuture;
//   int currentNewsIndex = 0;
//   int _currentPage = 0;
//   final PageController _pageController = PageController();
//   Timer? _autoSlideTimer;
//   int _autoSlideItemCount = 0;

//   @override
//   void initState() {
//     super.initState();
//     _newsFuture = _fetchTrendingNews();
//   }

//   @override
//   void dispose() {
//     _cancelAutoSlide();
//     _pageController.dispose();
//     super.dispose();
//   }

//   // Sửa đổi _fetchTrendingNews để dùng GNews API
//   Future<List<NewsItem>> _fetchTrendingNews() async {
//     final uri = Uri.https('gnews.io', '/api/v4/top-headlines', {
//       'token': GnewsApiKey,
//       'country': 'vn',
//       'category': 'sports',
//       'lang': 'en',
//       'max': '10',
//     });

//     final response = await http.get(uri);

//     if (response.statusCode != 200) {
//       throw Exception('HTTP ${response.statusCode} từ GNews.io');
//     }

//     final data = json.decode(response.body) as Map<String, dynamic>;
//     if (data['totalArticles'] == null) {
//       throw Exception(data['message'] ?? 'GNews.io trả về trạng thái lỗi');
//     }

//     final articles = (data['articles'] as List?) ?? [];
//     final mapped = articles
//         .whereType<Map<String, dynamic>>()
//         .map(NewsItem.fromGNewsJson)
//         .take(10)
//         .toList();

//     if (mapped.isEmpty) {
//       throw Exception('Không có tin tức hợp lệ từ GNews.io');
//     }

//     return mapped;
//   }

//   Future<void> refreshNews() async {
//     _cancelAutoSlide();
//     setState(() {
//       _newsFuture = _fetchTrendingNews();
//       currentNewsIndex = 0;
//       _currentPage = 0;
//     });
//     if (_pageController.hasClients) {
//       _pageController.jumpToPage(0);
//     }
//   }

//   // Hàm mở URL
//   void _launchUrl(String urlString) async {
//     if (urlString.isEmpty || !urlString.startsWith('http')) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Không tìm thấy liên kết bài báo hợp lệ.'),
//           ),
//         );
//       }
//       return;
//     }

//     final Uri url = Uri.parse(urlString);

//     if (await canLaunchUrl(url)) {
//       await launchUrl(url, mode: LaunchMode.externalApplication);
//     } else {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Không thể mở liên kết: $urlString')),
//         );
//       }
//     }
//   }

//   // Hàm chuyển tin tức
//   void _nextNews(int maxIndex) {
//     if (maxIndex <= 1 || !_pageController.hasClients) return;
//     final current = _pageController.page?.round() ?? _currentPage;
//     final target = current + 1;
//     _pageController.animateToPage(
//       target,
//       duration: const Duration(milliseconds: 400),
//       curve: Curves.easeInOut,
//     );
//     _restartAutoSlide(maxIndex);
//   }

//   void _previousNews(int maxIndex) {
//     if (maxIndex <= 1 || !_pageController.hasClients) return;
//     final current = _pageController.page?.round() ?? _currentPage;
//     final target = current - 1;
//     _pageController.animateToPage(
//       target,
//       duration: const Duration(milliseconds: 400),
//       curve: Curves.easeInOut,
//     );
//     _restartAutoSlide(maxIndex);
//   }

//   void _ensureAutoSlide(int maxIndex) {
//     if (maxIndex <= 1) {
//       _cancelAutoSlide();
//       return;
//     }
//     if (_autoSlideItemCount != maxIndex ||
//         _autoSlideTimer == null ||
//         !_autoSlideTimer!.isActive) {
//       _restartAutoSlide(maxIndex);
//     }
//   }

//   void _restartAutoSlide(int maxIndex) {
//     _cancelAutoSlide();
//     if (maxIndex <= 1 || !_pageController.hasClients) return;
//     _autoSlideItemCount = maxIndex;
//     _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
//       if (!mounted || !_pageController.hasClients) return;
//       final current = _pageController.page?.round() ?? _currentPage;
//       final target = current + 1;
//       _pageController.animateToPage(
//         target,
//         duration: const Duration(milliseconds: 400),
//         curve: Curves.easeInOut,
//       );
//     });
//   }

//   void _cancelAutoSlide() {
//     _autoSlideTimer?.cancel();
//     _autoSlideTimer = null;
//   }

//   // Widget hiển thị placeholder
//   Widget _buildPlaceholderOrVideoIcon(NewsItem item) {
//     return Container(
//       height: 140,
//       width: double.infinity,
//       color: Colors.grey[300],
//       child: const Center(
//         child: Icon(Icons.broken_image, color: Colors.grey, size: 30),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 18),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               const Text(
//                 'Trending Now',
//                 style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 10),
//         FutureBuilder<List<NewsItem>>(
//           future: _newsFuture,
//           builder: (context, snapshot) {
//             if (snapshot.connectionState == ConnectionState.waiting) {
//               return const SizedBox(
//                 height: 220,
//                 child: Center(child: CircularProgressIndicator()),
//               );
//             }
//             if (snapshot.hasError) {
//               return Padding(
//                 padding: const EdgeInsets.all(18),
//                 child: Text('Lỗi tải tin tức: ${snapshot.error}'),
//               );
//             }
//             if (!snapshot.hasData || snapshot.data!.isEmpty) {
//               return const Padding(
//                 padding: EdgeInsets.all(18),
//                 child: Text('Không có tin tức thịnh hành.'),
//               );
//             }

//             final news = snapshot.data!;
//             final maxIndex = news.length;

//             WidgetsBinding.instance.addPostFrameCallback((_) {
//               if (!mounted) return;
//               _ensureAutoSlide(maxIndex);
//             });

//             return Column(
//               children: [
//                 Padding(
//                   padding: const EdgeInsets.only(right: 8.0),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.end,
//                     children: [
//                       IconButton(
//                         icon: const Icon(Icons.arrow_back_ios, size: 16),
//                         onPressed: () => _previousNews(maxIndex),
//                       ),
//                       IconButton(
//                         icon: const Icon(Icons.arrow_forward_ios, size: 16),
//                         onPressed: () => _nextNews(maxIndex),
//                       ),
//                     ],
//                   ),
//                 ),
//                 SizedBox(
//                   height: 220,
//                   child: PageView.builder(
//                     controller: _pageController,
//                     onPageChanged: (index) {
//                       setState(() {
//                         _currentPage = index;
//                         currentNewsIndex = maxIndex == 0 ? 0 : index % maxIndex;
//                       });
//                       _restartAutoSlide(maxIndex);
//                     },
//                     itemBuilder: (context, index) {
//                       final item = news[index % maxIndex];
//                       return Padding(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 18,
//                           vertical: 6,
//                         ),
//                         child: InkWell(
//                           onTap: () => _launchUrl(item.url),
//                           borderRadius: BorderRadius.circular(14),
//                           child: ClipRRect(
//                             borderRadius: BorderRadius.circular(14),
//                             child: Column(
//                               children: [
//                                 CachedNetworkImage(
//                                   imageUrl: item.imageUrl,
//                                   height: 140,
//                                   width: double.infinity,
//                                   fit: BoxFit.contain,
//                                   placeholder: (context, url) => Container(
//                                     height: 140,
//                                     width: double.infinity,
//                                     color: Colors.grey[200],
//                                     child: const Center(
//                                       child: CircularProgressIndicator(
//                                         strokeWidth: 2,
//                                       ),
//                                     ),
//                                   ),
//                                   errorWidget: (context, url, error) =>
//                                       _buildPlaceholderOrVideoIcon(item),
//                                 ),
//                                 Container(
//                                   color: Colors.white,
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 14,
//                                     vertical: 10,
//                                   ),
//                                   child: Row(
//                                     children: [
//                                       const CircleAvatar(
//                                         backgroundColor: Colors.white,
//                                         radius: 15,
//                                         child: Icon(
//                                           Icons.sports,
//                                           color: Color(0xFF2196F3),
//                                           size: 18,
//                                         ),
//                                       ),
//                                       const SizedBox(width: 10),
//                                       Expanded(
//                                         child: Text(
//                                           item.title,
//                                           style: const TextStyle(
//                                             fontWeight: FontWeight.bold,
//                                             fontSize: 15,
//                                           ),
//                                           maxLines: 2,
//                                           overflow: TextOverflow.ellipsis,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//                 ),
//               ],
//             );
//           },
//         ),
//       ],
//     );
//   }
// }

// import 'package:flutter/material.dart';
// import 'package:http/http.dart' as http;
// import 'dart:convert';
// import 'package:cached_network_image/cached_network_image.dart';
// import 'package:url_launcher/url_launcher.dart';
// import 'dart:async';
// import '../../models/news_item.dart';

// class TrendingNewsSection extends StatefulWidget {
//   const TrendingNewsSection({super.key});

//   @override
//   State<TrendingNewsSection> createState() => TrendingNewsSectionState();
// }

// class TrendingNewsSectionState extends State<TrendingNewsSection> {
//   late Future<List<NewsItem>> _newsFuture;
//   int currentNewsIndex = 0;
//   int _currentPage = 0;
//   final PageController _pageController = PageController();
//   Timer? _autoSlideTimer;
//   int autoSlideItemCount = 0;

//   @override
//   void initState() {
//     super.initState();
//     _newsFuture = _fetchTrendingNews();
//   }

//   @override
//   void dispose() {
//     _cancelAutoSlide();
//     _pageController.dispose();
//     super.dispose();
//   }

//   // Hàm gọi API tin tức thể thao tự tạo
//   Future<List<NewsItem>> _fetchTrendingNews() async {
//     // QUAN TRỌNG: Thay đổi địa chỉ IP cho phù hợp với bạn!
//     // - Dùng 'http://10.0.2.2:5001' nếu bạn chạy trên máy ảo Android.
//     // - Dùng IP mạng LAN của máy tính (ví dụ: 'http://192.168.1.10:5001') nếu bạn chạy trên thiết bị thật.
//     const String apiUrl = 'http://10.0.2.2:5001/api/sports-news';

//     try {
//       final response = await http
//           .get(Uri.parse(apiUrl))
//           .timeout(const Duration(seconds: 15));

//       if (response.statusCode == 200) {
//         // API của bạn trả về một List, nên chúng ta decode nó thành List<dynamic>
//         // Sử dụng `utf8.decode(response.bodyBytes)` để đảm bảo hiển thị đúng tiếng Việt
//         final List<dynamic> articles = json.decode(
//           utf8.decode(response.bodyBytes),
//         );

//         // Dùng factory constructor `fromCustomApiJson` để chuyển đổi dữ liệu
//         final mapped = articles
//             .whereType<Map<String, dynamic>>()
//             .map(NewsItem.fromCustomApiJson)
//             .toList();

//         if (mapped.isEmpty) {
//           throw Exception('API không trả về tin tức nào.');
//         }

//         return mapped;
//       } else {
//         throw Exception(
//           'Không thể tải tin tức. Mã lỗi: ${response.statusCode}',
//         );
//       }
//     } on TimeoutException catch (_) {
//       throw Exception(
//         'Hết thời gian chờ kết nối đến server. Hãy đảm bảo API của bạn đang chạy.',
//       );
//     } catch (e) {
//       // Ném lại lỗi để FutureBuilder có thể bắt và hiển thị
//       rethrow;
//     }
//   }

//   Future<void> refreshNews() async {
//     _cancelAutoSlide();
//     setState(() {
//       _newsFuture = _fetchTrendingNews();
//       currentNewsIndex = 0;
//       _currentPage = 0;
//     });
//     if (_pageController.hasClients) {
//       _pageController.jumpToPage(0);
//     }
//   }

//   // Hàm mở URL trong trình duyệt ngoài
//   void _launchUrl(String urlString) async {
//     if (urlString.isEmpty || !urlString.startsWith('http')) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text('Không tìm thấy liên kết bài báo hợp lệ.'),
//           ),
//         );
//       }
//       return;
//     }

//     final Uri url = Uri.parse(urlString);
//     if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
//       if (mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(content: Text('Không thể mở liên kết: $urlString')),
//         );
//       }
//     }
//   }

//   // Các hàm điều khiển slider tự động
//   void _nextNews(int maxIndex) {
//     if (maxIndex <= 1 || !_pageController.hasClients) return;
//     final target = (_pageController.page?.round() ?? _currentPage) + 1;
//     _pageController.animateToPage(
//       target,
//       duration: const Duration(milliseconds: 400),
//       curve: Curves.easeInOut,
//     );
//     _restartAutoSlide(maxIndex);
//   }

//   void _previousNews(int maxIndex) {
//     if (maxIndex <= 1 || !_pageController.hasClients) return;
//     final target = (_pageController.page?.round() ?? _currentPage) - 1;
//     _pageController.animateToPage(
//       target,
//       duration: const Duration(milliseconds: 400),
//       curve: Curves.easeInOut,
//     );
//     _restartAutoSlide(maxIndex);
//   }

//   void _ensureAutoSlide(int maxIndex) {
//     if (maxIndex <= 1) return;
//     if (_autoSlideTimer == null || !_autoSlideTimer!.isActive) {
//       _restartAutoSlide(maxIndex);
//     }
//   }

//   void _restartAutoSlide(int maxIndex) {
//     _cancelAutoSlide();
//     if (maxIndex <= 1 || !_pageController.hasClients) return;
//     _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
//       if (!mounted || !_pageController.hasClients) return;
//       final target = (_pageController.page?.round() ?? _currentPage) + 1;
//       _pageController.animateToPage(
//         target,
//         duration: const Duration(milliseconds: 400),
//         curve: Curves.easeInOut,
//       );
//     });
//   }

//   void _cancelAutoSlide() {
//     _autoSlideTimer?.cancel();
//     _autoSlideTimer = null;
//   }

//   // Widget hiển thị khi ảnh bị lỗi
//   Widget _buildErrorImage() {
//     return Container(
//       height: 140,
//       width: double.infinity,
//       color: Colors.grey[300],
//       child: const Center(
//         child: Icon(Icons.broken_image, color: Colors.grey, size: 30),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 18),
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               const Text(
//                 'Tin tức thể thao',
//                 style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
//               ),
//             ],
//           ),
//         ),
//         const SizedBox(height: 10),
//         FutureBuilder<List<NewsItem>>(
//           future: _newsFuture,
//           builder: (context, snapshot) {
//             if (snapshot.connectionState == ConnectionState.waiting) {
//               return const SizedBox(
//                 height: 220,
//                 child: Center(child: CircularProgressIndicator()),
//               );
//             }
//             if (snapshot.hasError) {
//               return Padding(
//                 padding: const EdgeInsets.all(18),
//                 child: Text(
//                   'Lỗi tải tin tức: ${snapshot.error}',
//                   style: const TextStyle(color: Colors.red),
//                 ),
//               );
//             }
//             if (!snapshot.hasData || snapshot.data!.isEmpty) {
//               return const Padding(
//                 padding: EdgeInsets.all(18),
//                 child: Text('Không có tin tức nào.'),
//               );
//             }

//             final news = snapshot.data!;
//             final maxIndex = news.length;

//             WidgetsBinding.instance.addPostFrameCallback((_) {
//               if (mounted) _ensureAutoSlide(maxIndex);
//             });

//             return Column(
//               children: [
//                 Padding(
//                   padding: const EdgeInsets.only(right: 8.0),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.end,
//                     children: [
//                       IconButton(
//                         icon: const Icon(Icons.arrow_back_ios, size: 16),
//                         onPressed: () => _previousNews(maxIndex),
//                       ),
//                       IconButton(
//                         icon: const Icon(Icons.arrow_forward_ios, size: 16),
//                         onPressed: () => _nextNews(maxIndex),
//                       ),
//                     ],
//                   ),
//                 ),
//                 SizedBox(
//                   height: 220,
//                   child: PageView.builder(
//                     controller: _pageController,
//                     onPageChanged: (index) {
//                       setState(() {
//                         _currentPage = index;
//                         currentNewsIndex = maxIndex == 0 ? 0 : index % maxIndex;
//                       });
//                       _restartAutoSlide(maxIndex);
//                     },
//                     itemBuilder: (context, index) {
//                       final item = news[index % maxIndex];
//                       return Padding(
//                         padding: const EdgeInsets.symmetric(
//                           horizontal: 18,
//                           vertical: 6,
//                         ),
//                         child: InkWell(
//                           onTap: () => _launchUrl(item.url),
//                           borderRadius: BorderRadius.circular(14),
//                           child: ClipRRect(
//                             borderRadius: BorderRadius.circular(14),
//                             child: Column(
//                               children: [
//                                 CachedNetworkImage(
//                                   imageUrl: item.imageUrl,
//                                   height: 140,
//                                   width: double.infinity,
//                                   fit: BoxFit
//                                       .cover, // Đổi thành cover để lấp đầy
//                                   placeholder: (context, url) => Container(
//                                     height: 140,
//                                     width: double.infinity,
//                                     color: Colors.grey[200],
//                                     child: const Center(
//                                       child: CircularProgressIndicator(
//                                         strokeWidth: 2,
//                                       ),
//                                     ),
//                                   ),
//                                   errorWidget: (context, url, error) =>
//                                       _buildErrorImage(),
//                                 ),
//                                 Container(
//                                   width: double
//                                       .infinity, // Đảm bảo container chiếm hết chiều rộng
//                                   color: Colors.white,
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 14,
//                                     vertical: 10,
//                                   ),
//                                   child: Row(
//                                     children: [
//                                       CircleAvatar(
//                                         backgroundColor: Colors.blue.shade50,
//                                         radius: 15,
//                                         child: Text(
//                                           item.sourceName.isNotEmpty
//                                               ? item.sourceName[0]
//                                               : 'B',
//                                           style: const TextStyle(
//                                             color: Colors.blue,
//                                             fontWeight: FontWeight.bold,
//                                           ),
//                                         ),
//                                       ),
//                                       const SizedBox(width: 10),
//                                       Expanded(
//                                         child: Text(
//                                           item.title,
//                                           style: const TextStyle(
//                                             fontWeight: FontWeight.bold,
//                                             fontSize: 15,
//                                           ),
//                                           maxLines: 2,
//                                           overflow: TextOverflow.ellipsis,
//                                         ),
//                                       ),
//                                     ],
//                                   ),
//                                 ),
//                               ],
//                             ),
//                           ),
//                         ),
//                       );
//                     },
//                   ),
//                 ),
//               ],
//             );
//           },
//         ),
//       ],
//     );
//   }
// }
