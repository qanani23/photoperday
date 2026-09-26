import 'package:flutter/material.dart';
import 'package:photo_per_day/data/models/date_key.dart';
import 'package:photo_per_day/data/models/photo_entry.dart';

/// Centralized repository providing realistic mock photos for calendar testing.
class MockPhotoService {
  MockPhotoService._();
  static final MockPhotoService instance = MockPhotoService._();

  /// Default mock photo for Today (Sunday, March 15, 2026)
  static final PhotoEntry defaultTodayPhoto = PhotoEntry(
    date: DateTime(2026, 3, 15),
    title: 'Golden Afternoon Reflections',
    caption: 'Sunlight dancing on the water during a quiet afternoon stroll.',
    location: 'Echo Park Lake',
    timeFormatted: '4:20 PM',
    category: 'Nature',
    icon: Icons.wb_sunny_rounded,
    gradientColors: [const Color(0xFFE28743), const Color(0xFF873E23)],
  );

  /// Mock photo database keyed by normalized DateKey
  Map<DateKey, PhotoEntry>? _dateEntries;

  Map<DateKey, PhotoEntry> get _entries {
    if (_dateEntries is! Map<DateKey, PhotoEntry>) {
      _dateEntries = _generateMockEntries();
    }
    return _dateEntries!;
  }

  Map<DateKey, PhotoEntry> _generateMockEntries() {
    final map = <DateKey, PhotoEntry>{};

    // Helper to register entry
    void add(PhotoEntry entry) {
      map[entry.dateKey] = entry;
    }

    // --- MARCH 2026 ---
    add(
      PhotoEntry(
        date: DateTime(2026, 3, 1),
        title: 'Morning Roast',
        caption:
            'Quiet Sunday morning with freshly brewed single-origin espresso.',
        location: 'Downtown Cafe',
        timeFormatted: '8:30 AM',
        category: 'Coffee',
        icon: Icons.coffee_rounded,
        gradientColors: [const Color(0xFF7D5836), const Color(0xFF4A301A)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 2),
        title: 'Spring Meadow',
        caption: 'First green blades of early spring catching the morning dew.',
        location: 'Botanical Gardens',
        timeFormatted: '9:15 AM',
        category: 'Nature',
        icon: Icons.park_rounded,
        gradientColors: [const Color(0xFF5B7845), const Color(0xFF354E24)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 3),
        title: 'Park Run with Milo',
        caption: 'Golden retriever in full sprint across the sunlit grass.',
        location: 'Riverside Dog Park',
        timeFormatted: '11:00 AM',
        category: 'Pets',
        icon: Icons.pets_rounded,
        gradientColors: [const Color(0xFFC29B48), const Color(0xFF7F6023)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 4),
        title: 'Golden Hour Horizon',
        caption:
            'Deep amber sky melting into the distant silhouette of the hills.',
        location: 'Sunset Vista Point',
        timeFormatted: '6:10 PM',
        category: 'Sunset',
        icon: Icons.wb_twilight_rounded,
        gradientColors: [const Color(0xFFD46945), const Color(0xFF7E331B)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 5),
        title: 'Purple Twilight',
        caption: 'Soft pastel dusk sky over the tranquil quiet neighborhood.',
        location: 'Home Balcony',
        timeFormatted: '6:45 PM',
        category: 'Sky',
        icon: Icons.nights_stay_rounded,
        gradientColors: [const Color(0xFFA66472), const Color(0xFF582F3B)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 6),
        title: 'Friends & Sweet Tea',
        caption: 'Spontaneous afternoon catchup and warm pastry.',
        location: 'Artisan Bakery',
        timeFormatted: '3:20 PM',
        category: 'Friends',
        icon: Icons.groups_rounded,
        gradientColors: [const Color(0xFFC48E72), const Color(0xFF734833)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 7),
        title: 'Natural Light Portrait',
        caption: 'Warm smile captured by the big studio window.',
        location: 'Creative Loft',
        timeFormatted: '2:00 PM',
        category: 'Portrait',
        icon: Icons.face_rounded,
        gradientColors: [const Color(0xFF48423E), const Color(0xFF24201E)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 8),
        title: 'Pine Ridge Hike',
        caption: 'Overlook of the mountain pass shrouded in morning fog.',
        location: 'Pine Ridge Trail',
        timeFormatted: '10:45 AM',
        category: 'Outdoors',
        icon: Icons.terrain_rounded,
        gradientColors: [const Color(0xFF5E6D4E), const Color(0xFF313B26)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 9),
        title: 'Redwood Sanctuary',
        caption: 'Towering canopy filtering emerald beams of sunlight.',
        location: 'Muir Woods',
        timeFormatted: '1:15 PM',
        category: 'Nature',
        icon: Icons.forest_rounded,
        gradientColors: [const Color(0xFF3F543C), const Color(0xFF1E2D1B)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 10),
        title: 'Farm-to-Table Brunch',
        caption: 'Fresh sourdough toast, poached eggs, and wild berries.',
        location: 'The Rustic Table',
        timeFormatted: '11:30 AM',
        category: 'Food',
        icon: Icons.restaurant_rounded,
        gradientColors: [const Color(0xFF9E6534), const Color(0xFF553213)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 11),
        title: 'Watercolor Afternoon',
        caption: 'Vibrant brushstrokes and joyful creative messes.',
        location: 'Art Room',
        timeFormatted: '4:15 PM',
        category: 'Art',
        icon: Icons.palette_rounded,
        gradientColors: [const Color(0xFF567899), const Color(0xFF24435C)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 12),
        title: 'Rainy Day Reading',
        caption: 'Warm knit blanket, steaming tea, and a chapter book.',
        location: 'Cozy Nook',
        timeFormatted: '5:00 PM',
        category: 'Lifestyle',
        icon: Icons.menu_book_rounded,
        gradientColors: [const Color(0xFF8A6C58), const Color(0xFF4A3426)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 13),
        title: 'Foggy Coast',
        caption: 'Crashing Pacific swells under an overcast marine layer.',
        location: 'Bodega Bay',
        timeFormatted: '12:40 PM',
        category: 'Travel',
        icon: Icons.waves_rounded,
        gradientColors: [const Color(0xFF5A6369), const Color(0xFF2C3236)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 14),
        title: 'Late Night Studio',
        caption: 'Warm desk lamp illuminating sketches and handwritten notes.',
        location: 'Home Office',
        timeFormatted: '11:15 PM',
        category: 'Creative',
        icon: Icons.edit_note_rounded,
        gradientColors: [const Color(0xFF4C443C), const Color(0xFF26201B)],
      ),
    );

    // Day 15 is TODAY (Ring indicator) - Can have a photo or remain waiting for capture!

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 16),
        title: 'Urban Monoliths',
        caption: 'Glass facades reflecting geometric blue skies.',
        location: 'Financial Plaza',
        timeFormatted: '1:30 PM',
        category: 'Architecture',
        icon: Icons.location_city_rounded,
        gradientColors: [const Color(0xFF3D424A), const Color(0xFF1E2126)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 17),
        title: 'Reflections after Rain',
        caption: 'City sidewalks glowing with amber puddle mirrors.',
        location: 'Market Street',
        timeFormatted: '7:40 PM',
        category: 'Street',
        icon: Icons.water_drop_rounded,
        gradientColors: [const Color(0xFF484B52), const Color(0xFF24272D)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 18),
        title: 'Night Streetlamp Glow',
        caption: 'Empty crosswalk bathed in cinematic warm lights.',
        location: 'Old Town Square',
        timeFormatted: '10:20 PM',
        category: 'Night',
        icon: Icons.lightbulb_outline_rounded,
        gradientColors: [const Color(0xFF363A40), const Color(0xFF191C20)],
      ),
    );

    add(
      PhotoEntry(
        date: DateTime(2026, 3, 19),
        title: 'Subway Light Trail',
        caption: 'Departing train blur rushing into the tunnel darkness.',
        location: 'Central Station',
        timeFormatted: '6:15 PM',
        category: 'Transit',
        icon: Icons.train_rounded,
        gradientColors: [const Color(0xFF54575E), const Color(0xFF2C2F36)],
      ),
    );

    // --- FEBRUARY 2026 ---
    final febTints = [
      [const Color(0xFF2C3238), const Color(0xFF15191D)],
      [const Color(0xFF26333D), const Color(0xFF121A20)],
      [const Color(0xFF38322E), const Color(0xFF1E1A17)],
      [const Color(0xFF2B2E33), const Color(0xFF15171B)],
      [const Color(0xFF3D322B), const Color(0xFF1F1813)],
      [const Color(0xFF2E353B), const Color(0xFF161C20)],
      [const Color(0xFF2F383D), const Color(0xFF171F22)],
    ];

    for (int day = 1; day <= 28; day++) {
      final tintPair = febTints[day % febTints.length];
      add(
        PhotoEntry(
          date: DateTime(2026, 2, day),
          title: 'February Memory #$day',
          caption: 'Winter moment preserved in the February archive.',
          location: 'City Archive',
          timeFormatted: '${(day % 12) + 1}:00 PM',
          category: 'Archive',
          icon: Icons.history_rounded,
          gradientColors: tintPair,
        ),
      );
    }

    return map;
  }

  /// Returns the photo entry for a given date, or null if none exists
  PhotoEntry? getPhoto(DateTime date) {
    return _entries[DateKey.fromDateTime(date)];
  }

  /// True if a photo was recorded on that date
  bool hasPhoto(DateTime date) {
    return _entries.containsKey(DateKey.fromDateTime(date));
  }

  /// Returns the photo entry for a given DateKey, or null if none exists
  PhotoEntry? getPhotoByKey(DateKey key) {
    return _entries[key];
  }

  /// True if a photo was recorded for that DateKey
  bool hasPhotoByKey(DateKey key) {
    return _entries.containsKey(key);
  }
}
