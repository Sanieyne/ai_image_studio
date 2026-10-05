import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../services/auth_service.dart';
import 'cloud_api_service.dart';

/// Client for real-time GPU instance provisioning status streaming over WebSocket.
/// Route: /ws/instance-status?token=ACCESS_TOKEN&instanceId=INSTANCE_ID
///
/// Features:
/// - Connects to WebSocket on cloud backend
/// - Automatically captures authentication errors (close code 1008 or auth error messages)
/// - Triggers silent token refresh on auth failure
/// - If refresh fails, cleanly triggers [AuthService.instance.handleSessionExpired]
///   so the user is redirected to the login screen instead of hanging silently.
class InstanceStatusClient {
  static final InstanceStatusClient instance = InstanceStatusClient._();
  InstanceStatusClient._();

  WebSocket? _socket;
  StreamSubscription? _subscription;
  String? _currentInstanceId;
  bool _isRefreshing = false;

  /// Current active instance ID
  String? get currentInstanceId => _currentInstanceId;

  /// Translates HTTP base URL to WebSocket base URL
  Uri get wsBaseUri {
    final httpUri = Uri.parse(CloudApiService.instance.baseUrl);
    final wsScheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    final portPart = httpUri.hasPort ? ':${httpUri.port}' : '';
    // Strip trailing /api/v1 if present to target /ws/instance-status
    return Uri.parse('$wsScheme://${httpUri.host}$portPart/ws/instance-status');
  }

  /// Connect to status stream for [instanceId].
  Future<void> connect({
    required String instanceId,
    required void Function(Map<String, dynamic> statusPayload) onStatusUpdate,
    void Function(String error)? onError,
  }) async {
    await disconnect();
    _currentInstanceId = instanceId;

    await _connectInternal(
      instanceId: instanceId,
      onStatusUpdate: onStatusUpdate,
      onError: onError,
    );
  }

  Future<void> _connectInternal({
    required String instanceId,
    required void Function(Map<String, dynamic> statusPayload) onStatusUpdate,
    void Function(String error)? onError,
  }) async {
    final token = AuthService.instance.accessToken;
    if (token == null || token.isEmpty) {
      debugPrint('[InstanceStatusClient] No access token available. Triggering session expiry.');
      await AuthService.instance.handleSessionExpired();
      onError?.call('Authentication token required.');
      return;
    }

    final targetUri = wsBaseUri.replace(queryParameters: {
      'token': token,
      'instanceId': instanceId,
    });

    try {
      final ws = await WebSocket.connect(targetUri.toString()).timeout(
        const Duration(seconds: 10),
      );
      _socket = ws;

      _subscription = ws.listen(
        (data) {
          try {
            final parsed = jsonDecode(data.toString()) as Map<String, dynamic>;
            final type = parsed['type'] as String?;

            if (type == 'ERROR') {
              final msg = parsed['message']?.toString() ?? 'Unknown WebSocket error';
              debugPrint('[InstanceStatusClient] Server ERROR: $msg');

              if (_isAuthError(msg)) {
                _handleAuthFailure(
                  instanceId: instanceId,
                  onStatusUpdate: onStatusUpdate,
                  onError: onError,
                );
                return;
              }
              onError?.call(msg);
            } else if (type == 'STATUS_UPDATE') {
              onStatusUpdate(parsed);
            }
          } catch (e) {
            debugPrint('[InstanceStatusClient] Failed to parse message: $e');
          }
        },
        onError: (e) {
          debugPrint('[InstanceStatusClient] WebSocket error: $e');
          onError?.call(e.toString());
        },
        onDone: () {
          final code = ws.closeCode;
          final reason = ws.closeReason ?? '';
          debugPrint('[InstanceStatusClient] WebSocket closed (code: $code, reason: $reason)');

          // Code 1008 indicates policy violation / auth failure
          if (code == 1008 || code == 4401 || _isAuthError(reason)) {
            _handleAuthFailure(
              instanceId: instanceId,
              onStatusUpdate: onStatusUpdate,
              onError: onError,
            );
          }
        },
        cancelOnError: false,
      );
    } catch (e) {
      debugPrint('[InstanceStatusClient] Connection failed: $e');
      if (_isAuthError(e.toString())) {
        await _handleAuthFailure(
          instanceId: instanceId,
          onStatusUpdate: onStatusUpdate,
          onError: onError,
        );
      } else {
        onError?.call('Connection error: $e');
      }
    }
  }

  bool _isAuthError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('jwt expired') ||
        lower.contains('authentication failed') ||
        lower.contains('token expired') ||
        lower.contains('unauthorized') ||
        lower.contains('token required') ||
        lower.contains('invalid token');
  }

  Future<void> _handleAuthFailure({
    required String instanceId,
    required void Function(Map<String, dynamic> statusPayload) onStatusUpdate,
    void Function(String error)? onError,
  }) async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    try {
      debugPrint('[InstanceStatusClient] Auth failed on WebSocket. Attempting silent token refresh...');
      final refreshed = await AuthService.instance.refreshTokens();

      if (refreshed) {
        debugPrint('[InstanceStatusClient] Token refreshed successfully. Reconnecting WebSocket...');
        await disconnect();
        _connectInternal(
          instanceId: instanceId,
          onStatusUpdate: onStatusUpdate,
          onError: onError,
        );
      } else {
        debugPrint('[InstanceStatusClient] Token refresh failed. Forcing logout & redirect to login.');
        await disconnect();
        await AuthService.instance.handleSessionExpired();
        onError?.call('Session expired. Redirecting to login.');
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Disconnects and cleans up listeners
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}
