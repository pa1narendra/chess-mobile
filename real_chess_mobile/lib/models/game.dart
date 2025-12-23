class Game {
  final String id;
  final String hostName;
  final String timeControl;
  final bool isBot;

  Game({
    required this.id,
    required this.hostName,
    required this.timeControl,
    required this.isBot,
  });

  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: json['id'] ?? '',
      hostName: json['hostName'] ?? 'Unknown',
      timeControl: json['timeControl'] ?? '10+0',
      isBot: json['isBot'] ?? false,
    );
  }
}
