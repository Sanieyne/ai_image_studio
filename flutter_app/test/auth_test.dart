import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:ai_image_studio/screens/login_screen.dart';
import 'package:ai_image_studio/screens/register_screen.dart';
import 'package:ai_image_studio/services/api_client.dart';
import 'package:ai_image_studio/services/auth_service.dart';
import 'package:ai_image_studio/widgets/auth_form_widgets.dart';

const _baseUrl = 'https://test.local/api/v1';

Map<String, dynamic> _userJson({String username = 'pixelartist7'}) => {
      '_id': '68d000000000000000000001',
      'username': username,
      'email': 'pix@example.com',
      'role': 'user',
      'credits': 100,
      'totalCreditsPurchased': 0,
      'totalCreditsUsed': 0,
      'isActive': true,
      'isEmailVerified': false,
      'lastLoginAt': '2026-09-29T00:00:00.000Z',
      'storageQuotaGB': 20,
      'storageUsedGB': 0,
      'selectedModels': ['sdxl-base-1.0'],
      'displayName': username,
      'avatarUrl': null,
      'bio': '',
      'isPublicProfile': true,
    };

http.Response _sessionResponse({
  int status = 200,
  String access = 'access-1',
  String refresh = 'refresh-1',
}) =>
    http.Response(
      jsonEncode({
        'success': true,
        'message': 'ok',
        'data': {
          'user': _userJson(),
          'accessToken': access,
          'refreshToken': refresh,
        },
      }),
      status,
      headers: {'Content-Type': 'application/json'},
    );

http.Response _refreshResponse({
  String access = 'access-2',
  String refresh = 'refresh-2',
}) =>
    http.Response(
      // NOTE: matches the real backend — refresh carries NO user object.
      jsonEncode({
        'success': true,
        'message': 'Tokens refreshed successfully',
        'data': {'accessToken': access, 'refreshToken': refresh},
      }),
      200,
      headers: {'Content-Type': 'application/json'},
    );

http.Response _errorResponse(int status, String message,
        [List<String> errors = const []]) =>
    http.Response(
      jsonEncode({
        'success': false,
        'message': message,
        if (errors.isNotEmpty) 'errors': errors,
      }),
      status,
      headers: {'Content-Type': 'application/json'},
    );

/// Fake backend with a request log, shaped exactly like cloud_backend.
class FakeBackend {
  final List<http.BaseRequest> requests = [];
  final Map<String, http.Response Function(http.BaseRequest)> handlers = {};

  Future<http.Response> handle(http.BaseRequest request) async {
    requests.add(request);
    final handler = handlers[request.url.path];
    if (handler != null) return handler(request);
    return _errorResponse(404, 'Not found');
  }

  List<http.BaseRequest> callsTo(String path) =>
      requests.where((r) => r.url.path == path).toList();
}

AuthService _service(FakeBackend backend, SecureTokenStore store) =>
    AuthService.forTest(
      httpClient: MockClient(backend.handle),
      tokenStore: store,
      baseUrl: _baseUrl,
    );

void main() {
  group('AuthValidators mirror the backend registerSchema', () {
    test('username: required, alphanum, 3-30 chars', () {
      expect(AuthValidators.username(null), 'Username is required');
      expect(AuthValidators.username('  '), 'Username is required');
      expect(AuthValidators.username('ab'),
          'Username must be at least 3 characters');
      expect(AuthValidators.username('a' * 31),
          'Username cannot exceed 30 characters');
      expect(AuthValidators.username('no-dashes'),
          'Username must only contain alphanumeric characters');
      expect(AuthValidators.username('has space'),
          'Username must only contain alphanumeric characters');
      expect(AuthValidators.username('abc'), isNull);
      expect(AuthValidators.username('User123'), isNull);
      expect(AuthValidators.username('a' * 30), isNull);
    });

    test('email: required, valid format', () {
      expect(AuthValidators.email(null), 'Email is required');
      expect(AuthValidators.email(''), 'Email is required');
      expect(AuthValidators.email('not-an-email'),
          'Please provide a valid email address');
      expect(
          AuthValidators.email('a@b'), 'Please provide a valid email address');
      expect(AuthValidators.email('pix@example.com'), isNull);
    });

    test('register password: 8+ chars with upper, lower, digit', () {
      expect(AuthValidators.registerPassword(null), 'Password is required');
      expect(AuthValidators.registerPassword('Sh0rt!'),
          'Password must be at least 8 characters long');
      expect(AuthValidators.registerPassword('alllowercase1'),
          contains('uppercase letter'));
      expect(AuthValidators.registerPassword('ALLUPPERCASE1'),
          contains('uppercase letter'));
      expect(AuthValidators.registerPassword('NoDigitsHere'),
          contains('uppercase letter'));
      expect(AuthValidators.registerPassword('Valid123'), isNull);
    });

    test('login password: presence only', () {
      expect(AuthValidators.loginPassword(null), 'Password is required');
      expect(AuthValidators.loginPassword(''), 'Password is required');
      expect(AuthValidators.loginPassword('anything'), isNull);
    });
  });

  group('AuthService session lifecycle', () {
    test('login stores tokens + user and notifies listeners', () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/auth/login'] = (_) => _sessionResponse();
      final store = InMemoryTokenStore();
      final auth = _service(backend, store);

      var notifications = 0;
      auth.addListener(() => notifications++);

      final user = await auth.login('pix@example.com', 'Valid123');

      expect(user.username, 'pixelartist7');
      expect(user.credits, 100);
      expect(auth.status, AuthStatus.authenticated);
      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?.email, 'pix@example.com');
      expect(await store.read(AuthService.accessTokenKey), 'access-1');
      expect(await store.read(AuthService.refreshTokenKey), 'refresh-1');
      expect(notifications, greaterThan(0));

      // Request body matches the backend loginSchema.
      final req = backend.callsTo('/api/v1/auth/login').single
          as http.Request;
      expect(jsonDecode(req.body), {
        'email': 'pix@example.com',
        'password': 'Valid123',
        'deviceLabel': AuthService.deviceLabel,
      });
    });

    test('register (201) starts a session', () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/auth/register'] = (_) =>
          _sessionResponse(status: 201);
      final auth = _service(backend, InMemoryTokenStore());

      final user =
          await auth.register('pixelartist7', 'pix@example.com', 'Valid123');

      expect(user.username, 'pixelartist7');
      expect(auth.isAuthenticated, isTrue);
      final req = backend.callsTo('/api/v1/auth/register').single
          as http.Request;
      expect(
        jsonDecode(req.body),
        {
          'username': 'pixelartist7',
          'email': 'pix@example.com',
          'password': 'Valid123',
          'deviceLabel': AuthService.deviceLabel,
        },
      );
    });

    test('signOut ends this session on the server, then clears locally',
        () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/auth/login'] = (_) => _sessionResponse();
      backend.handlers['/api/v1/auth/logout'] = (_) => http.Response(
            jsonEncode({
              'success': true,
              'data': {'revoked': true}
            }),
            200,
          );
      final store = InMemoryTokenStore();
      final auth = _service(backend, store);
      await auth.login('pix@example.com', 'Valid123');

      await auth.signOut();

      final req =
          backend.callsTo('/api/v1/auth/logout').single as http.Request;
      expect(jsonDecode(req.body), {'refreshToken': 'refresh-1'});
      expect(auth.isAuthenticated, isFalse);
      expect(await store.read(AuthService.accessTokenKey), isNull);
      expect(await store.read(AuthService.refreshTokenKey), isNull);
    });

    test('signOut still clears locally when the server is unreachable',
        () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/auth/login'] = (_) => _sessionResponse();
      backend.handlers['/api/v1/auth/logout'] =
          (_) => throw http.ClientException('offline');
      final store = InMemoryTokenStore();
      final auth = _service(backend, store);
      await auth.login('pix@example.com', 'Valid123');

      await auth.signOut();

      expect(backend.callsTo('/api/v1/auth/logout'), hasLength(1));
      expect(auth.isAuthenticated, isFalse);
      expect(await store.read(AuthService.refreshTokenKey), isNull);
    });

    test('signOut with no session makes no server call', () async {
      final backend = FakeBackend();
      final auth = _service(backend, InMemoryTokenStore());
      await auth.signOut();
      expect(backend.callsTo('/api/v1/auth/logout'), isEmpty);
      expect(auth.isAuthenticated, isFalse);
    });

    test('login 401 surfaces server message, stores nothing', () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/auth/login'] = (_) =>
          _errorResponse(401, 'Invalid email or password.');
      final store = InMemoryTokenStore();
      final auth = _service(backend, store);

      await expectLater(
        auth.login('pix@example.com', 'wrong'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'Invalid email or password.',
          ),
        ),
      );
      expect(auth.isAuthenticated, isFalse);
      expect(await store.read(AuthService.accessTokenKey), isNull);
      expect(await store.read(AuthService.refreshTokenKey), isNull);
    });

    test('server validation details are surfaced, not swallowed', () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/auth/register'] = (_) => _errorResponse(
            400,
            'Validation Error',
            ['Password must be at least 8 characters long'],
          );
      final auth = _service(backend, InMemoryTokenStore());

      await expectLater(
        auth.register('ab', 'bad', 'x'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('Password must be at least 8 characters long'),
          ),
        ),
      );
    });

    test('register → restart → session persists → logout', () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/auth/register'] = (_) =>
          _sessionResponse(status: 201);
      backend.handlers['/api/v1/auth/refresh'] = (_) => _refreshResponse();
      backend.handlers['/api/v1/users/me'] = (_) => http.Response(
            jsonEncode({'success': true, 'data': _userJson()}),
            200,
            headers: {'Content-Type': 'application/json'},
          );
      // One store shared across "restarts", like secure storage on disk.
      final store = InMemoryTokenStore();

      // 1. Register on first launch.
      final firstLaunch = _service(backend, store);
      await firstLaunch.register(
          'pixelartist7', 'pix@example.com', 'Valid123');
      expect(firstLaunch.isAuthenticated, isTrue);

      // 2. Simulate app restart: brand-new service, same store.
      final restarted = _service(backend, store);
      expect(restarted.status, AuthStatus.unknown);
      expect(restarted.currentUser, isNull);

      // 3. Launch restore silently refreshes + reloads the profile.
      expect(await restarted.restoreSession(), isTrue);
      expect(restarted.isAuthenticated, isTrue);
      expect(restarted.currentUser?.username, 'pixelartist7');
      // Tokens rotated by the refresh during restore.
      expect(await store.read(AuthService.accessTokenKey), 'access-2');
      expect(await store.read(AuthService.refreshTokenKey), 'refresh-2');

      // 4. Logout wipes everything and flips status for the login gate.
      await restarted.logout();
      expect(restarted.status, AuthStatus.unauthenticated);
      expect(restarted.currentUser, isNull);
      expect(restarted.accessToken, isNull);
      expect(await store.read(AuthService.accessTokenKey), isNull);
      expect(await store.read(AuthService.refreshTokenKey), isNull);
      expect(await restarted.isLoggedIn(), isFalse);
    });

    test('restore with no stored session returns false', () async {
      final backend = FakeBackend();
      final auth = _service(backend, InMemoryTokenStore());
      expect(await auth.restoreSession(), isFalse);
      expect(auth.status, AuthStatus.unauthenticated);
      expect(backend.requests, isEmpty); // no pointless network call
    });
  });

  group('401 → silent refresh → retry (ApiClient)', () {
    test('expired access token is refreshed and request retried once',
        () async {
      final backend = FakeBackend();
      final seenAuthHeaders = <String?>[];
      backend.handlers['/api/v1/generations/me'] = (req) {
        seenAuthHeaders.add(req.headers['Authorization']);
        // First attempt uses the expired token → 401; retry uses the new one.
        if (seenAuthHeaders.length == 1) {
          return _errorResponse(401, 'Authentication token expired');
        }
        return http.Response(
          jsonEncode({'success': true, 'data': [], 'pagination': {}}),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      };
      backend.handlers['/api/v1/auth/refresh'] = (_) => _refreshResponse();

      final store = InMemoryTokenStore();
      final auth = _service(backend, store);
      // Seed an expired access token + valid refresh token.
      await store.write(AuthService.accessTokenKey, 'expired-access');
      await store.write(AuthService.refreshTokenKey, 'valid-refresh');
      await auth.init();

      final client = ApiClient(
        authService: auth,
        httpClient: MockClient(backend.handle),
        baseUrl: _baseUrl,
      );
      final res = await client.get('/generations/me');

      expect(res.statusCode, 200);
      expect(backend.callsTo('/api/v1/generations/me'), hasLength(2));
      expect(backend.callsTo('/api/v1/auth/refresh'), hasLength(1));
      // Bearer attached on both attempts; retry used the rotated token.
      expect(seenAuthHeaders[0], 'Bearer expired-access');
      expect(seenAuthHeaders[1], 'Bearer access-2');
      expect(auth.isAuthenticated, isTrue);
      expect(auth.accessToken, 'access-2');
    });

    test('malformed refresh token → logout so the gate redirects to login',
        () async {
      final backend = FakeBackend();
      backend.handlers['/api/v1/generations/me'] = (_) =>
          _errorResponse(401, 'Invalid authentication token');
      backend.handlers['/api/v1/auth/refresh'] = (_) =>
          _errorResponse(401, 'Invalid or expired refresh token.');

      final store = InMemoryTokenStore();
      final auth = _service(backend, store);
      await store.write(AuthService.accessTokenKey, 'garbage');
      await store.write(AuthService.refreshTokenKey, 'garbage');
      await auth.init();
      expect(auth.isAuthenticated, isTrue);

      final client = ApiClient(
        authService: auth,
        httpClient: MockClient(backend.handle),
        baseUrl: _baseUrl,
      );
      final res = await client.get('/generations/me');

      // Original 401 propagates; exactly one refresh was attempted…
      expect(res.statusCode, 401);
      expect(backend.callsTo('/api/v1/auth/refresh'), hasLength(1));
      expect(backend.callsTo('/api/v1/generations/me'), hasLength(1));
      // …and the failed refresh destroyed the session.
      expect(auth.status, AuthStatus.unauthenticated);
      expect(auth.isAuthenticated, isFalse);
      expect(await store.read(AuthService.accessTokenKey), isNull);
      expect(await store.read(AuthService.refreshTokenKey), isNull);
    });

    test('handleSessionExpired destroys tokens and transitions to unauthenticated',
        () async {
      final backend = FakeBackend();
      final store = InMemoryTokenStore();
      final auth = _service(backend, store);
      await store.write(AuthService.accessTokenKey, 'active-access');
      await store.write(AuthService.refreshTokenKey, 'active-refresh');
      await auth.init();
      expect(auth.isAuthenticated, isTrue);

      await auth.handleSessionExpired();

      expect(auth.status, AuthStatus.unauthenticated);
      expect(auth.isAuthenticated, isFalse);
      expect(await store.read(AuthService.accessTokenKey), isNull);
      expect(await store.read(AuthService.refreshTokenKey), isNull);
    });

    test('concurrent 401s share a single refresh call', () async {
      final backend = FakeBackend();
      var protectedCalls = 0;
      backend.handlers['/api/v1/generations/me'] = (_) {
        protectedCalls++;
        if (protectedCalls <= 2) {
          return _errorResponse(401, 'Authentication token expired');
        }
        return http.Response(
          jsonEncode({'success': true, 'data': [], 'pagination': {}}),
          200,
          headers: {'Content-Type': 'application/json'},
        );
      };
      var refreshCalls = 0;
      backend.handlers['/api/v1/auth/refresh'] = (_) {
        refreshCalls++;
        return _refreshResponse();
      };

      final store = InMemoryTokenStore();
      final auth = _service(backend, store);
      await store.write(AuthService.accessTokenKey, 'expired-access');
      await store.write(AuthService.refreshTokenKey, 'valid-refresh');
      await auth.init();

      final client = ApiClient(
        authService: auth,
        httpClient: MockClient(backend.handle),
        baseUrl: _baseUrl,
      );
      final results = await Future.wait([
        client.get('/generations/me'),
        client.get('/generations/me'),
      ]);

      expect(results.map((r) => r.statusCode), [200, 200]);
      expect(refreshCalls, 1);
    });
  });

  group('Auth screens (offline validation)', () {
    testWidgets('login blocks empty submit with inline errors', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(onShowRegister: () {})),
      );

      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });

    testWidgets('login rejects malformed email', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: LoginScreen(onShowRegister: () {})),
      );

      await tester.enterText(find.byType(TextFormField).first, 'not-an-email');
      await tester.tap(find.text('Sign In'));
      await tester.pump();

      expect(
        find.text('Please provide a valid email address'),
        findsOneWidget,
      );
    });

    testWidgets('register enforces the backend password rule', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RegisterScreen(onShowLogin: () {})),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'validuser1');
      await tester.enterText(
          find.byType(TextFormField).at(1), 'pix@example.com');
      await tester.enterText(find.byType(TextFormField).at(2), 'weak');
      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(
        find.text('Password must be at least 8 characters long'),
        findsOneWidget,
      );
    });

    testWidgets('register rejects non-alphanumeric usernames', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: RegisterScreen(onShowLogin: () {})),
      );

      await tester.enterText(find.byType(TextFormField).at(0), 'bad-name!');
      await tester.tap(find.text('Create Account'));
      await tester.pump();

      expect(
        find.text('Username must only contain alphanumeric characters'),
        findsOneWidget,
      );
    });
  });
}
