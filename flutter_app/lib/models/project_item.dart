/// SQLite-backed studio project.
class ProjectItem {
  final String id;
  String title;
  bool isPinned;
  final DateTime createdAt;
  DateTime updatedAt;

  ProjectItem({
    required this.id,
    required this.title,
    this.isPinned = false,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'is_pinned': isPinned ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory ProjectItem.fromMap(Map<String, dynamic> map) => ProjectItem(
        id: map['id'] as String,
        title: map['title'] as String,
        isPinned: (map['is_pinned'] as int) == 1,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        updatedAt:
            DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      );
}
