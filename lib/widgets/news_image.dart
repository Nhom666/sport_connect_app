import 'package:flutter/material.dart';
import '../models/news_item.dart';

class NewsImage extends StatelessWidget {
  final NewsItem newsItem;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const NewsImage({
    super.key,
    required this.newsItem,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    // Nếu không có ảnh hợp lệ, hiển thị error widget
    if (!newsItem.hasValidImage) {
      return errorWidget ??
          Container(
            width: width,
            height: height ?? 200,
            color: Colors.grey[300],
            child: const Icon(
              Icons.image_not_supported,
              color: Colors.grey,
              size: 48,
            ),
          );
    }

    // Nếu là data URL, decode và hiển thị bằng Image.memory
    if (newsItem.isDataUrl) {
      final bytes = newsItem.getDataUrlBytes();
      if (bytes != null && bytes.isNotEmpty) {
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) {
            return errorWidget ??
                Container(
                  width: width,
                  height: height ?? 200,
                  color: Colors.grey[300],
                  child: const Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                    size: 48,
                  ),
                );
          },
        );
      } else {
        // Nếu decode thất bại hoặc bytes rỗng, hiển thị error
        print('Failed to decode data URL or empty bytes: ${newsItem.imageUrl}');
        return errorWidget ??
            Container(
              width: width,
              height: height ?? 200,
              color: Colors.grey[300],
              child: const Icon(
                Icons.broken_image,
                color: Colors.grey,
                size: 48,
              ),
            );
      }
    }

    // Nếu là network URL thông thường, sử dụng Image.network
    return Image.network(
      newsItem.imageUrl,
      width: width,
      height: height,
      fit: fit,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return placeholder ??
            Container(
              width: width,
              height: height ?? 200,
              color: Colors.grey[200],
              child: const Center(child: CircularProgressIndicator()),
            );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ??
            Container(
              width: width,
              height: height ?? 200,
              color: Colors.grey[300],
              child: const Icon(
                Icons.broken_image,
                color: Colors.grey,
                size: 48,
              ),
            );
      },
    );
  }
}
