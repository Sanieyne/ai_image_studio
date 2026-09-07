/// LoRA API models matching POST /loras/* contracts.
class LoraConfig {
  final String pathOrId;
  final String? adapterName;
  final double weight;

  const LoraConfig({
    required this.pathOrId,
    this.adapterName,
    this.weight = 0.8,
  });

  Map<String, dynamic> toJson() => {
        'path_or_id': pathOrId,
        if (adapterName != null) 'adapter_name': adapterName,
        'weight': weight,
      };
}

class LoraInfo {
  final String path;
  final double weight;

  const LoraInfo({required this.path, required this.weight});

  factory LoraInfo.fromJson(Map<String, dynamic> json) => LoraInfo(
        path: json['path'] as String? ?? '',
        weight: (json['weight'] as num?)?.toDouble() ?? 0.8,
      );
}
