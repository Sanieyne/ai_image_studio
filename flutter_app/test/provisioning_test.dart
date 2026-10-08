import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_image_studio/features/cloud_mode/data/services/instance_status_client.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/screens/instance_provisioning_screen.dart';
import 'package:ai_image_studio/features/cloud_mode/presentation/widgets/active_instances_panel.dart';

/// GET /gpu/instances/:id as the backend returns it.
Map<String, dynamic> instanceJson({
  String status = 'provisioning',
  String stage = 'engine_starting',
  String message = 'The GPU is running. Installing and starting the engine (this can take several minutes).',
  int elapsed = 125,
  double charged = 0.16,
  double refunded = 0,
  String? failureReason,
  List<Map<String, dynamic>> logs = const [],
}) =>
    {
      '_id': 'inst1',
      'status': status,
      'gpuType': 'RTX 4060 Ti',
      'progress': {
        'stage': stage,
        'message': message,
        'portFound': true,
        'engineReachable': false,
        'failureReason': failureReason,
        'models': [
          {'modelId': 'realesrgan-x4plus', 'status': 'queued', 'progressPercent': 0},
        ],
      },
      'elapsedSeconds': elapsed,
      'billing': {'creditsCharged': charged, 'creditsRefunded': refunded, 'creditsPerHour': 4.62},
      'provisioningLogs': logs,
    };

Widget host(Widget child) => MaterialApp(home: child);

/// The provisioning screen pulses forever, so pumpAndSettle never returns;
/// advance enough time for dialogs to open or close instead.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('WebSocket URL', () {
    test('keeps the REST prefix (/ai-api) and drops /api/v1', () {
      expect(InstanceStatusClient.wsUriFor('https://cosmic-gen.com/ai-api/api/v1').toString(),
          'wss://cosmic-gen.com/ai-api/ws/instance-status');
      expect(InstanceStatusClient.wsUriFor('http://localhost:5000/api/v1/').toString(),
          'ws://localhost:5000/ws/instance-status');
    });
  });

  group('provisioning screen', () {
    testWidgets('without a live socket it polls the instance and shows the real step, time and credits',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1100));
      var calls = 0;
      await tester.pumpWidget(host(InstanceProvisioningScreen(
        instanceId: 'inst1',
        gpuName: 'RTX 4060 Ti',
        selectedModelIds: const ['realesrgan-x4plus'],
        isDark: false,
        disableAutoConnect: true, // the socket never connects
        pollInterval: const Duration(seconds: 5),
        fetchInstance: (id) async {
          calls += 1;
          expect(id, 'inst1');
          return instanceJson(elapsed: 120 + calls * 5);
        },
      )));
      await tester.pump(); // first poll right away
      await tester.pump();
      expect(calls, 1);
      expect(find.byKey(const ValueKey('provisioning_step_message')), findsOneWidget);
      expect(find.textContaining('Installing and starting the engine'), findsOneWidget);
      expect(find.text('Elapsed 2:05 · Charged so far 0.16 credits'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(calls, 2, reason: 'polls every 5 s while the socket is down');
      // The server's 130 s, plus at most one local tick landing in the same frame.
      final elapsed = tester.widget<Text>(find.byKey(const ValueKey('provisioning_elapsed_credits'))).data!;
      expect(elapsed, matches(RegExp(r'^Elapsed 2:1[01] · Charged so far 0\.16 credits$')));

      // Server unreachable: said plainly, polling continues.
      await tester.pumpWidget(host(InstanceProvisioningScreen(
        key: const ValueKey('second'),
        instanceId: 'inst1',
        isDark: false,
        disableAutoConnect: true,
        fetchInstance: (_) async => null,
      )));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('provisioning_connection_note')), findsOneWidget);
      expect(find.textContaining("Can't reach the server"), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a failure shows the reason and what was charged and refunded, never "not billed"',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1100));
      await tester.pumpWidget(host(InstanceProvisioningScreen(
        instanceId: 'inst1',
        isDark: false,
        disableAutoConnect: true,
        fetchInstance: (_) async => instanceJson(
          status: 'failed',
          stage: 'failed',
          charged: 1.5,
          refunded: 1.5,
          failureReason: 'The engine could not start: GPU RTX 9090 (sm_130) is not supported.',
        ),
      )));
      await tester.pump();
      await tester.pump();
      expect(find.text('Launch Failed'), findsOneWidget);
      final subtitle = tester.widget<Text>(find.byKey(const ValueKey('provisioning_subtitle'))).data!;
      expect(subtitle, contains('sm_130'));
      expect(subtitle, contains('1.50 credits were charged and refunded in full.'));
      expect(find.textContaining('You have not been billed'), findsNothing);
      expect(find.byKey(const ValueKey('stop_instance_btn')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Stop asks for confirmation, stops the instance and reports the refund', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1100));
      final stopped = <String>[];
      await tester.pumpWidget(host(InstanceProvisioningScreen(
        instanceId: 'inst1',
        isDark: false,
        disableAutoConnect: true,
        fetchInstance: (_) async => instanceJson(),
        stopInstance: (id) async {
          stopped.add(id);
          return {'_id': id, 'status': 'stopped', 'creditsCharged': 0.16, 'creditsRefunded': 0.16};
        },
      )));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('stop_instance_btn')));
      await settle(tester);
      expect(find.text('Stop this GPU?'), findsOneWidget);
      expect(find.textContaining('everything charged for it is refunded'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_stop_instance')));
      await tester.pump();
      await tester.pump();

      expect(stopped, ['inst1']);
      expect(find.text('GPU Stopped'), findsOneWidget);
      final subtitle = tester.widget<Text>(find.byKey(const ValueKey('provisioning_subtitle'))).data!;
      expect(subtitle, 'You stopped this GPU. 0.16 credits were charged and refunded in full.');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cancelling the confirmation keeps the GPU running', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1100));
      var stops = 0;
      await tester.pumpWidget(host(InstanceProvisioningScreen(
        instanceId: 'inst1',
        isDark: false,
        disableAutoConnect: true,
        fetchInstance: (_) async => instanceJson(),
        stopInstance: (_) async {
          stops += 1;
          return null;
        },
      )));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('stop_instance_btn')));
      await settle(tester);
      await tester.tap(find.text('Keep running'));
      await settle(tester);
      expect(stops, 0);
      expect(find.text('GPU Stopped'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Cloud screen: active GPUs', () {
    testWidgets('lists each active GPU with status and cost, and stops it after confirmation', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      final stopped = <String>[];
      final instances = [
        instanceJson(),
        {
          '_id': 'inst2',
          'status': 'ready',
          'gpuType': 'RTX 3090',
          'billing': {'creditsCharged': 3.2, 'creditsPerHour': 9.2},
        },
      ];
      await tester.pumpWidget(host(Scaffold(
        body: ActiveInstancesPanel(
          instances: instances,
          onStop: (i) async => stopped.add(ActiveInstancesPanel.idOf(i)),
          onOpen: (_) {},
        ),
      )));
      expect(find.text('Your active GPUs'), findsOneWidget);
      expect(find.textContaining('Installing and starting the engine'), findsOneWidget);
      expect(find.textContaining('4.62 credits/hr · charged 0.16'), findsOneWidget);
      expect(find.textContaining('Ready · 9.20 credits/hr · charged 3.20'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('stop_active_inst2')));
      await tester.pumpAndSettle();
      expect(find.text('Stop RTX 3090?'), findsOneWidget);
      expect(find.textContaining('Time used so far stays charged'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('confirm_stop_active_instance')));
      await tester.pumpAndSettle();
      expect(stopped, ['inst2']);
    });
  });
}
