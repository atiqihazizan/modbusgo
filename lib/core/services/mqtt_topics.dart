// MQTT topic builder — padan backend v3 (mqtt-handlers.js).
// Base: LoRa/tracking/{device_id}/{kind}
class MqttTopics {
  const MqttTopics(this.deviceId);
  final String deviceId;

  static const String _base = 'LoRa/tracking';

  String get bundle => '$_base/$deviceId/bundle';
  String get status => '$_base/$deviceId/status';
  String get backfill => '$_base/$deviceId/backfill';
  String get ack => '$_base/$deviceId/ack';
}
