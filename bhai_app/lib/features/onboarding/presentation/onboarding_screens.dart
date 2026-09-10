import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';

class OnboardingScreens extends StatefulWidget {
  const OnboardingScreens({super.key});

  @override
  State<OnboardingScreens> createState() => _OnboardingScreensState();
}

class _OnboardingScreensState extends State<OnboardingScreens> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, String>> _onboardingData = [
    {
      'title': 'Welcome to BHAI',
      'desc': 'A simple way to ask trusted contacts and nearby opted-in BHAI users for help when you feel unsafe.',
    },
    {
      'title': 'Volunteer Support Network',
      'desc': 'Opt in to receive nearby help requests. Your exact location is never shared with a helper until they choose to acknowledge an active emergency.',
    },
    {
      'title': 'Secure Platform Shield',
      'desc': 'During an emergency, BHAI saves your last known location and location history for authorized responders. You control trusted contacts and helper availability.',
    }
  ];

  Future<void> _requestAllPermissions() async {
    // Request only the permissions needed for the selected safety features.
    await Permission.location.request();
    await Permission.notification.request();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (page) => setState(() => _currentPage = page),
                  itemCount: _onboardingData.length + 2, // Extra screens for Permissions & Contacts
                  itemBuilder: (context, index) {
                    if (index < _onboardingData.length) {
                      return _buildSlide(_onboardingData[index]['title']!, _onboardingData[index]['desc']!);
                    } else if (index == _onboardingData.length) {
                      return _buildPermissionsSlide();
                    } else {
                      return _buildContactsSlide();
                    }
                  },
                ),
              ),
              _buildBottomControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlide(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.security, size: 100, color: AppTheme.accentCyan),
          const SizedBox(height: 40),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Text(
            desc,
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsSlide() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security, size: 70, color: AppTheme.accentCyan),
            const SizedBox(height: 20),
            Text(
              'Permissions Rationale',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Bhai needs these permissions so it can help you during an emergency, including when your phone has limited connectivity.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            _permissionTile('Location', 'Captures initial and live GPS position during active emergency mode.', Permission.location),
            _permissionTile('Bluetooth / BLE', 'Discovers nearby opted-in devices to relay emergency alerts offline.', Permission.bluetoothScan),
            _permissionTile('Notifications', 'Shows active emergency status and alerts you when a nearby user needs help.', Permission.notification),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: _requestAllPermissions,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Request / Retry'),
                ),
                FilledButton.icon(
                  onPressed: () => openAppSettings(),
                  icon: const Icon(Icons.settings),
                  label: const Text('System Settings'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionTile(String title, String desc, Permission permission) {
    return FutureBuilder<PermissionStatus>(
      future: permission.status,
      builder: (context, snapshot) {
        final granted = snapshot.data?.isGranted ?? false;
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              Icon(granted ? Icons.check_circle : Icons.warning_amber, color: granted ? Colors.green : Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(desc, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContactsSlide() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.people_alt_outlined, size: 80, color: AppTheme.accentCyan),
          const SizedBox(height: 30),
          Text(
            'Trusted Emergency Circle',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          const Text(
            'After secure sign-in, add the people you trust. BHAI will notify active trusted contacts when you confirm an emergency request.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: AppTheme.accentCyan,
              side: const BorderSide(color: AppTheme.accentCyan, width: 2),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            icon: const Icon(Icons.shield),
            label: const Text('Start Using Bhai'),
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final totalPages = _onboardingData.length + 2;
    final isLastPage = _currentPage == totalPages - 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Pagination Indicator dots
          Row(
            children: List.generate(totalPages, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 4.0),
                height: 8.0,
                width: _currentPage == index ? 24.0 : 8.0,
                decoration: BoxDecoration(
                  color: _currentPage == index ? AppTheme.accentCyan : Colors.grey.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(4.0),
                ),
              );
            }),
          ),
          // Actions
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isLastPage ? AppTheme.accentCrimson : AppTheme.accentCyan,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () {
              if (isLastPage) {
                context.go('/home');
              } else {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeIn,
                );
              }
            },
            child: Text(isLastPage ? 'Get Started' : 'Next'),
          ),
        ],
      ),
    );
  }
}
