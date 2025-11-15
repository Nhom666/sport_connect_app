import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import '../models/news_item.dart';
import '../service/news_api_service.dart';
import 'news_image.dart';

class SportsNewsSection extends StatefulWidget {
  const SportsNewsSection({super.key});

  @override
  State<SportsNewsSection> createState() => SportsNewsSectionState();
}

class SportsNewsSectionState extends State<SportsNewsSection> {
  late Future<List<NewsItem>> _newsFuture;
  final NewsApiService _apiService = NewsApiService();

  int _currentPage = 0;
  final PageController _pageController = PageController();
  Timer? _autoSlideTimer;

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  @override
  void dispose() {
    _cancelAutoSlide();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> refreshNews() async {
    _cancelAutoSlide();
    _loadNews();
    await _newsFuture;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  void _loadNews() {
    setState(() {
      _newsFuture = _apiService.fetchNews();
    });
  }

  Future<void> _launchUrl(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      // Xử lý lỗi nếu cần
    }
  }

  void _nextNews(int maxIndex) {
    if (maxIndex <= 1 || !_pageController.hasClients) return;
    final target = (_pageController.page?.round() ?? _currentPage) + 1;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    _restartAutoSlide(maxIndex);
  }

  void _previousNews(int maxIndex) {
    if (maxIndex <= 1 || !_pageController.hasClients) return;
    final target = (_pageController.page?.round() ?? _currentPage) - 1;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    _restartAutoSlide(maxIndex);
  }

  void _ensureAutoSlide(int maxIndex) {
    if (maxIndex <= 1) return;
    if (_autoSlideTimer == null || !_autoSlideTimer!.isActive) {
      _restartAutoSlide(maxIndex);
    }
  }

  void _restartAutoSlide(int maxIndex) {
    _cancelAutoSlide();
    if (maxIndex <= 1 || !_pageController.hasClients) return;
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final target = (_pageController.page?.round() ?? _currentPage) + 1;
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    });
  }

  void _cancelAutoSlide() {
    _autoSlideTimer?.cancel();
    _autoSlideTimer = null;
  }

  Widget _buildErrorImage() {
    return Container(
      height: 120,
      width: double.infinity,
      color: Colors.grey[300],
      child: const Center(
        child: Icon(Icons.broken_image, color: Colors.grey, size: 30),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            "Trending Now",
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 250, // Giảm chiều cao
          child: FutureBuilder<List<NewsItem>>(
            future: _newsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Lỗi: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('Không có tin tức nào.'));
              }

              final newsList = snapshot.data!;
              final maxIndex = newsList.length;

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _ensureAutoSlide(maxIndex);
              });

              return Column(
                children: [
                  // Các nút điều khiển - Giảm padding
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0, bottom: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios, size: 16),
                          onPressed: () => _previousNews(maxIndex),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios, size: 16),
                          onPressed: () => _nextNews(maxIndex),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  // PageView
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      onPageChanged: (index) {
                        setState(() {
                          _currentPage = index;
                        });
                        _restartAutoSlide(maxIndex);
                      },
                      itemBuilder: (context, index) {
                        final item = newsList[index % maxIndex];
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4, // Giảm padding
                          ),
                          child: InkWell(
                            onTap: () => _launchUrl(item.link),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min, // THÊM DÒ NÀY
                                children: [
                                  // Hình ảnh - Giảm chiều cao
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(14),
                                    ),
                                    child: NewsImage(
                                      newsItem: item,
                                      height: 120, // Giảm từ 140 xuống 120
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      placeholder: Container(
                                        height: 120,
                                        color: Colors.grey[200],
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: _buildErrorImage(),
                                    ),
                                  ),
                                  // Thông tin tin tức - Giảm padding
                                  Flexible(
                                    // Thêm Flexible
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                        10.0,
                                      ), // Giảm từ 12 xuống 10
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Avatar - Giảm kích thước
                                          CircleAvatar(
                                            backgroundColor:
                                                Colors.blue.shade50,
                                            radius: 14, // Giảm từ 16 xuống 14
                                            child: Text(
                                              item.source.isNotEmpty
                                                  ? item.source[0].toUpperCase()
                                                  : 'B',
                                              style: const TextStyle(
                                                color: Colors.blue,
                                                fontWeight: FontWeight.bold,
                                                fontSize:
                                                    12, // Giảm từ 14 xuống 12
                                              ),
                                            ),
                                          ),
                                          const SizedBox(
                                            width: 8,
                                          ), // Giảm từ 10 xuống 8
                                          // Title
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize
                                                  .min, // THÊM DÒNG NÀY
                                              children: [
                                                Text(
                                                  item.title,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize:
                                                        13, // Giảm từ 14 xuống 13
                                                    height:
                                                        1.2, // Giảm line height
                                                  ),
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(
                                                  height: 2,
                                                ), // Giảm từ 4 xuống 2
                                                Text(
                                                  item.source,
                                                  style: TextStyle(
                                                    fontSize:
                                                        10, // Giảm từ 11 xuống 10
                                                    color: Colors.grey.shade600,
                                                    fontStyle: FontStyle.italic,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ],
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
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
