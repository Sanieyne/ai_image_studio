import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_image_studio/features/cloud_mode/data/models/cloud_model.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/screens/cloud_management_screen.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/widgets/gpu_recommendation_card.dart';

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

    final mockOffer = MarketplaceOffer(
      id: '12345',
      provider: 'vastai',
      gpuName: 'RTX 4090',
      vramGB: 24.0,
      numGpus: 1,
      totalFlops: 82.5,
      pricePerHour: 0.44,
      dphBase: 0.44,
      storageCostPerHour: 0.01,
      bandwidthCostPerGB: 0.02,
      totalHourlyCost: 0.45,
      inetUp: 500,
      inetDown: 1000,
      reliability: 0.99,
      cudaVersion: 12.4,
      driverVersion: '550.54',
      geolocation: 'US-East',
      directPortCount: 1,
      cpuCores: 8,
      ramGB: 32.0,
      diskGB: 100,
      dlperf: 30.0,
      verified: true,
      rentable: true,
      headroomVramGB: 8.0,
      fit: 'optimal',
      fitReason: 'Great fit for test model',
      estimatedDownloadTimeMinutes: 2.0,
    );

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
}
