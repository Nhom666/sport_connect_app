// custom_dropdown_widget.dart
import 'package:flutter/material.dart';
import '../utils/constants.dart'; // <-- Import hằng số của bạn

class CustomDropdownWidget extends StatefulWidget {
  final String title;
  final List<String> items;
  final String? selectedItem;
  final Function(String?) onChanged;

  const CustomDropdownWidget({
    Key? key,
    required this.title,
    required this.items,
    this.selectedItem,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<CustomDropdownWidget> createState() => _CustomDropdownWidgetState();
}

class _CustomDropdownWidgetState extends State<CustomDropdownWidget> {
  final GlobalKey _buttonKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _isDropdownOpened = false;

  // --- Giả sử màu này từ file constants.dart ---
  // Nếu không, bạn có thể thay thế kPrimaryColor
  // bằng const Color(0xFF1976D2)
  static const Color _highlightColor = Color(0xFF1976D2);

  void _openDropdown() {
    if (_overlayEntry == null) {
      final RenderBox renderBox =
          _buttonKey.currentContext!.findRenderObject() as RenderBox;
      final size = renderBox.size;
      final position = renderBox.localToGlobal(Offset.zero);

      _overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          left: position.dx,
          top: position.dy + size.height + 8, // Thêm 8px khoảng cách
          width: size.width,
          child: Material(
            elevation: 8.0,
            borderRadius: kDefaultBorderRadius, // <-- Dùng hằng số
            color: Colors.white,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: kDefaultBorderRadius,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              // --- UPDATED: Thêm ConstrainedBox và SingleChildScrollView ---
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: 250, // <-- Giới hạn chiều cao
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.items.map((item) {
                      final isSelected = item == widget.selectedItem;
                      return InkWell(
                        onTap: () {
                          _closeDropdown();
                          widget.onChanged(item);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          width: double.infinity,
                          decoration: isSelected
                              ? BoxDecoration(
                                  // <-- Cập nhật màu
                                  color: _highlightColor.withOpacity(0.1),
                                )
                              : null,
                          child: Text(
                            item,
                            style: TextStyle(
                              fontSize: 16,
                              color: isSelected
                                  ? _highlightColor // <-- Cập nhật màu
                                  : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              // --------------------------------------------------------
            ),
          ),
        ),
      );

      Overlay.of(context).insert(_overlayEntry!);
      setState(() {
        _isDropdownOpened = true;
      });
    }
  }

  void _closeDropdown() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      setState(() {
        _isDropdownOpened = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        // --- UPDATED: Sửa style của nút để khớp với TextField ---
        GestureDetector(
          key: _buttonKey,
          onTap: _isDropdownOpened ? _closeDropdown : _openDropdown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey[200], // <-- Giống TextField
              borderRadius: kDefaultBorderRadius, // <-- Dùng hằng số
              // Bỏ border và shadow
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.selectedItem ?? 'Select ${widget.title}',
                    style: TextStyle(
                      fontSize: 16,
                      color: widget.selectedItem != null
                          ? Colors.black
                          : Colors.grey[700], // <-- Giống hintText
                    ),
                  ),
                ),
                Icon(
                  _isDropdownOpened
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 24,
                  color: _isDropdownOpened
                      ? _highlightColor // <-- Cập nhật màu
                      : Colors.grey[700],
                ),
              ],
            ),
          ),
        ),
        // ----------------------------------------------------
      ],
    );
  }
}
