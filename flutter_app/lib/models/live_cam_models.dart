class LiveCamPreset {
  final String name;
  final String filename;
  final String path;

  LiveCamPreset({
    required this.name,
    required this.filename,
    required this.path,
  });

  factory LiveCamPreset.fromJson(Map<String, dynamic> json) {
    return LiveCamPreset(
      name: json['name'] as String? ?? 'Preset',
      filename: json['filename'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }
}

class LiveCamStatusResult {
  final bool success;
  final String message;
  final bool active;
  final String? sourceName;
  final String? streamUrl;

  LiveCamStatusResult({
    required this.success,
    required this.message,
    this.active = false,
    this.sourceName,
    this.streamUrl,
  });

  factory LiveCamStatusResult.fromJson(Map<String, dynamic> json) {
    return LiveCamStatusResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      active: json['active'] as bool? ?? false,
      sourceName: json['source_name'] as String?,
      streamUrl: json['stream_url'] as String?,
    );
  }
}

class LiveCamFrameResult {
  final bool active;
  final double fps;
  final String sourceName;
  final bool enhanceFace;
  final bool mirror;
  final String? frameBase64;
  final String? message;

  LiveCamFrameResult({
    required this.active,
    required this.fps,
    required this.sourceName,
    this.enhanceFace = false,
    this.mirror = true,
    this.frameBase64,
    this.message,
  });

  factory LiveCamFrameResult.fromJson(Map<String, dynamic> json) {
    return LiveCamFrameResult(
      active: json['active'] as bool? ?? false,
      fps: (json['fps'] as num?)?.toDouble() ?? 0.0,
      sourceName: json['source_name'] as String? ?? 'None',
      enhanceFace: json['enhance_face'] as bool? ?? false,
      mirror: json['mirror'] as bool? ?? true,
      frameBase64: json['frame_base64'] as String?,
      message: json['message'] as String?,
    );
  }
}
