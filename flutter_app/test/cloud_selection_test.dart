import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/features/cloud_mode/data/models/cloud_model.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/screens/cloud_management_screen.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/widgets/gpu_recommendation_card.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/widgets/storage_inspector_widget.dart';

/// An offer as the server sends it: credits only, priced for [storageGB].
MarketplaceOffer serverOffer({
  String id = '12345',
  int storageGB = 50,
  double? compute = 27.5,
  double? storage = 0.87,
  double? total = 28.37,
}) =>
    MarketplaceOffer(
      id: id,
      provider: 'vastai',
      gpuName: 'RTX 4090',
      vramGB: 24.0,
      numGpus: 1,
      totalFlops: 82.5,
      inetUp: 500,
      inetDown: 1000,
      reliability: 0.99,
      cudaVersion: 12.4,
      driverVersion: '550.54',
      geolocation: 'US-East',
      directPortCount: 1,
      cpuCores: 8,
      ramGB: 32.0,
      diskGB: 314,
      dlperf: 30.0,
      verified: true,
      rentable: true,
      headroomVramGB: 8.0,
      fit: 'optimal',
      fitReason: 'Great fit for test model',
      estimatedDownloadTimeMinutes: 2.0,
      storageGB: storageGB,
      computeCreditsPerHour: compute,
      storageCreditsPerGBMonth: 12.5,
      storageCreditsPerHour: storage,
      totalCreditsPerHour: total,
      bandwidthDownCreditsPerGB: 0.2441,
      bandwidthUpCreditsPerGB: 0.2441,
    );

void main() {
  testWidgets('CloudManagementScreen starts with 0 models and 0 GPUs selected', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CloudManagementScreen(isDark: true),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify selection prompt is visible
    final promptFinder = find.byKey(const ValueKey('gpu_selection_prompt'));
    expect(promptFinder, findsOneWidget);
    expect(find.descendant(of: promptFinder, matching: find.text('No Models Selected')), findsOneWidget);
    expect(find.descendant(of: promptFinder, matching: find.text('Select a model to see personalized recommendations')), findsOneWidget);

    // Verify launch button is disabled with message
    expect(find.text('Select a model to continue'), findsOneWidget);

    final launchBtnFinder = find.byKey(const ValueKey('gpu_card_launch_btn'));
    expect(launchBtnFinder, findsOneWidget);
    final elevatedButton = tester.widget<ElevatedButton>(launchBtnFinder);
    expect(elevatedButton.onPressed, isNull, reason: 'Launch button must be disabled when no model is selected');
  });

  testWidgets('GpuRecommendationCard separates recommendation from selection', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));

    final requirements = <String, dynamic>{
      'modelCount': 1,
      'totalModelSizeGB': 6.5,
      'baseOverheadGB': 2.0,
      'bufferGB': 1.5,
      'totalWithBufferGB': 10.0,
      'maxVramGB': 12.0,
      'minVramGB': 10.0,
    };

    final mockOffer = serverOffer();

    final marketplaceResult = MarketplaceRecommendedResult(
      requirements: requirements,
      balancedOffer: mockOffer,
      cheapestOffer: mockOffer,
      fastestOffer: mockOffer,
      mostReliableOffer: mockOffer,
      allOffers: [mockOffer],
    );

    MarketplaceOffer? selectedFromCallback;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GpuRecommendationCard(
            result: null,
            marketplaceResult: marketplaceResult,
            selectedOffer: null, // User has NOT tapped/selected any GPU
            hasModelSelection: true, // User selected a model
            onSelectOffer: (offer) => selectedFromCallback = offer,
            isDark: true,
            onLaunchInstance: (_) {},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify recommendation banner is displayed because hasModelSelection is true and userSelectedOffer is null
    expect(find.text('Top recommendation for your models — tap it to select'), findsOneWidget);
    expect(find.text('Select this GPU'), findsOneWidget);

    // Verify launch button is still disabled because user hasn't selected an offer yet
    expect(find.text('Select a GPU offer to continue'), findsOneWidget);
    final elevatedButton = tester.widget<ElevatedButton>(find.byKey(const ValueKey('gpu_card_launch_btn')));
    expect(elevatedButton.onPressed, isNull);

    // Tap "Select this GPU" button on the hero
    await tester.tap(find.byKey(const ValueKey('select_recommended_btn')));
    expect(selectedFromCallback?.id, equals('12345'));
  });

  testWidgets('offer card and side panel show the same total for the same offer and storage size',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    final offer = serverOffer();
    final requests = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: GpuRecommendationCard(
                  result: null,
                  marketplaceResult: MarketplaceRecommendedResult(
                    requirements: const {},
                    balancedOffer: offer,
                    allOffers: [offer],
                  ),
                  selectedOffer: offer,
                  hasModelSelection: true,
                  onSelectOffer: (_) {},
                  isDark: false,
                  onLaunchInstance: (_) {},
                ),
              ),
              Expanded(
                child: StorageInspectorWidget(
                  result: null,
                  selectedOffer: offer,
                  initialStorageGB: 50,
                  isDark: false,
                  // The server's estimate for the same offer and size.
                  fetchEstimate: ({required String offerId, required int storageGB}) async {
                    requests.add('$offerId@$storageGB');
                    return LivePricingEstimate(
                      offerId: offerId,
                      gpuName: 'RTX 4090',
                      storageGB: storageGB,
                      priceAvailable: true,
                      computeCreditsPerHour: 27.5,
                      storageCreditsPerGBMonth: 12.5,
                      storageCreditsPerHour: 0.87,
                      totalCreditsPerHour: 28.37,
                      bandwidthDownCreditsPerGB: 0.2441,
                      bandwidthUpCreditsPerGB: 0.2441,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requests, ['12345@50']);
    final cardTotal = tester.widget<Text>(find.byKey(const ValueKey('gpu_card_total_rate'))).data;
    final panelTotal = tester.widget<Text>(find.byKey(const ValueKey('storage_panel_total_rate'))).data;
    expect(cardTotal, '28.37 credits/hr');
    expect(panelTotal, cardTotal);
    // Both Rent buttons quote the same rate.
    expect(find.text('Rent & Launch RTX 4090 (28.37 credits/hr)'), findsNWidgets(2));
    // Bandwidth shows download and upload, billed by usage.
    expect(find.textContaining('↓ 0.2441'), findsWidgets);
    expect(find.textContaining('↑ 0.2441'), findsWidgets);
  });

  testWidgets('an offer the server could not price shows "price unavailable" and cannot be rented',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final offer = serverOffer(compute: null, storage: null, total: null);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GpuRecommendationCard(
            result: null,
            marketplaceResult: MarketplaceRecommendedResult(
              requirements: const {},
              balancedOffer: offer,
              allOffers: [offer],
            ),
            selectedOffer: offer,
            hasModelSelection: true,
            onSelectOffer: (_) {},
            isDark: false,
            onLaunchInstance: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const ValueKey('gpu_card_total_rate'))).data, 'price unavailable');
    final button = tester.widget<ElevatedButton>(find.byKey(const ValueKey('gpu_card_launch_btn')));
    expect(button.onPressed, isNull);
    expect(find.text('Rent unavailable: price unavailable'), findsOneWidget);
  });

  test('offers parse server prices; older server field names still work', () {
    final current = MarketplaceOffer.fromJson({
      'id': '1',
      'storageGB': 100,
      'computeCreditsPerHour': 3.75,
      'storageCreditsPerHour': 1.74,
      'totalCreditsPerHour': 5.49,
      'bandwidthDownCreditsPerGB': 0.1628,
      'bandwidthUpCreditsPerGB': 0.2441,
    });
    expect(current.totalCreditsPerHour, 5.49);
    expect(current.storageGB, 100);
    final older = MarketplaceOffer.fromJson({'id': '2', 'creditsPerHour': 3.75, 'bandwidthCreditsPerGB': 0.2});
    expect(older.computeCreditsPerHour, 3.75);
    expect(older.bandwidthDownCreditsPerGB, 0.2);
    expect(older.totalCreditsPerHour, isNull);
    final unpriced = MarketplaceOffer.fromJson({'id': '3', 'priceAvailable': false, 'totalCreditsPerHour': 9.9});
    expect(unpriced.priceAvailable, isFalse);
  });

  testWidgets('while rentals are paused the marketplace stays browsable but Rent is off, with the reason',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final offer = serverOffer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GpuRecommendationCard(
            result: null,
            marketplaceResult: MarketplaceRecommendedResult(
              requirements: const {},
              balancedOffer: offer,
              allOffers: [offer],
            ),
            selectedOffer: offer,
            hasModelSelection: true,
            onSelectOffer: (_) {},
            isDark: false,
            onLaunchInstance: (_) {},
            rentDisabledReason: 'Cloud GPU rentals are paused while we upgrade them.',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Prices still show...
    expect(tester.widget<Text>(find.byKey(const ValueKey('gpu_card_total_rate'))).data, '28.37 credits/hr');
    // ...but the button is disabled and says why.
    final button = tester.widget<ElevatedButton>(find.byKey(const ValueKey('gpu_card_launch_btn')));
    expect(button.onPressed, isNull);
    expect(find.text('Cloud GPU rentals are paused while we upgrade them.'), findsOneWidget);
  });
}
