// booking_screen.dart
import 'package:flutter/material.dart';
// NEW: Import the constants file
import '../utils/constants.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data should be fetched from a service, this is for UI demonstration
  final List<Map<String, String>> sports = [
    {'icon': '🎾', 'name': 'Tennis'},
    {'icon': '🏀', 'name': 'Basketball'},
    {'icon': '🏐', 'name': 'Volleyball'},
    {'icon': '🥏', 'name': 'Flying disc'},
    {'icon': '🏓', 'name': 'Table Tennis'},
    {'icon': '⚽️', 'name': 'Soccer'},
    {'icon': '🏸', 'name': 'Badminton'},
    {'icon': '🎳', 'name': 'Bowling'},
    {'icon': '🎱', 'name': 'Billiards'},
    {'icon': '🏈', 'name': 'American Football'},
  ];

  final List<Map<String, dynamic>> bookings = [
    // ... data remains the same
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // NEW & IMPROVED: Replaced the overlay logic with a modal bottom sheet
  void _showSportPickerModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SportPickerDialog(sports: sports),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Booking',
          style: TextStyle(
            color: kPrimaryColor,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: kWhiteColor,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () {}),
          IconButton(icon: const Icon(Icons.search), onPressed: () {}),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: kAccentColor,
          labelColor: Colors.black,
          unselectedLabelColor: kGreyColor,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Last Booking'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookingTab(), // Tab for 'All'
          _buildBookingTab(), // Tab for 'Last Booking' (can be customized later)
        ],
      ),
    );
  }

  Widget _buildBookingTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(kDefaultPadding),
      child: Column(
        children: [
          _buildCreateBookingButton(),
          const SizedBox(height: kDefaultPadding),
          _buildBookingList(),
        ],
      ),
    );
  }

  Widget _buildCreateBookingButton() {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccentColor,
          foregroundColor: kWhiteColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: _showSportPickerModal,
        icon: const Icon(Icons.add),
        label: const Text(
          'Create new Booking',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildBookingList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final booking = bookings[index];
        return ListTile(
          leading: Text(booking['icon'], style: const TextStyle(fontSize: 28)),
          title: Text(booking['name']),
          subtitle: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(booking['address']),
              Text('• ${booking['distance']}'),
              const Icon(Icons.star, color: Colors.amber, size: 16),
              Text('${booking['rating']}'),
            ],
          ),
          trailing: const Icon(Icons.chevron_right),
          contentPadding: EdgeInsets.zero,
        );
      },
    );
  }
}

// NEW & IMPROVED: Extracted the Sport Picker Dialog into its own stateless widget
class _SportPickerDialog extends StatefulWidget {
  final List<Map<String, String>> sports;
  const _SportPickerDialog({required this.sports});

  @override
  State<_SportPickerDialog> createState() => _SportPickerDialogState();
}

class _SportPickerDialogState extends State<_SportPickerDialog> {
  int _selectedSportPage = 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(kSmallPadding),
      child: Container(
        padding: const EdgeInsets.all(kDefaultPadding),
        decoration: BoxDecoration(
          color: kWhiteColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearchAndFilterBar(),
            const SizedBox(height: 12),
            _buildSportGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Row(
      children: [
        const Icon(Icons.search, color: kGreyColor, size: 24),
        const SizedBox(width: kSmallPadding),
        const Expanded(
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search',
              border: InputBorder.none,
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: kSmallPadding),
        Text('View', style: TextStyle(color: kGreyColor)),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down, color: kGreyColor),
        const SizedBox(width: kSmallPadding),
        Icon(Icons.filter_alt_outlined, color: Colors.grey[700]),
      ],
    );
  }

  Widget _buildSportGrid() {
    const int itemsPerPage = 8;
    final int pageCount = (widget.sports.length / itemsPerPage).ceil();

    return Column(
      children: [
        SizedBox(
          height: 180,
          child: PageView.builder(
            itemCount: pageCount,
            onPageChanged: (index) =>
                setState(() => _selectedSportPage = index),
            itemBuilder: (context, pageIndex) {
              final pageSports = widget.sports
                  .skip(pageIndex * itemsPerPage)
                  .take(itemsPerPage)
                  .toList();
              return GridView.builder(
                itemCount: pageSports.length,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 0.8,
                ),
                itemBuilder: (context, index) {
                  final sport = pageSports[index];
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        sport['icon']!,
                        style: const TextStyle(fontSize: 32),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sport['name']!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            pageCount,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _selectedSportPage == index
                    ? Colors.black54
                    : Colors.grey[300],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
