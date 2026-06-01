/// Abstract interface for device identity storage backends.
abstract class DeviceIdentityStorage {
  /// Reads the value associated with [key], or null if not found.
  Future<String?> read(String key);

  /// Writes [value] for [key].
  Future<void> write(String key, String value);

  /// Deletes the entry for [key].
  Future<void> delete(String key);
}
