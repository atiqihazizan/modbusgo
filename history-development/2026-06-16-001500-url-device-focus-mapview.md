# URL Device Focus — MapViewScreen

**Tarikh:** 2026-06-16 00:15 (UTC+8)

## Tujuan
Apabila pengguna buka Map View dari HomeScreen, URL WebView dihantar bersama parameter `?device=XXX` supaya peta web auto-focus kepada device ini.

## Fail Diubah

### `lib/presentation/map_view_screen/map_view_screen.dart`
- Tambah import `local_storage_service.dart`
- Tambah fungsi `_buildUrl()` — baca `device_id` dari `LocalStorageService`, bina URL dengan `?device=XXX`
- Tukar `body` kepada `FutureBuilder<String>` — tunggu URL siap sebelum render `LoraWebViewWidget`
- Jika tiada device ID dalam storage → guna URL asal tanpa parameter

## Aliran
```
Klik "Map View" → _buildUrl() baca LocalStorage
  → ada device_id  : https://lora2u.com/v2/?device=ABC123
  → tiada device_id: https://lora2u.com/v2/ (skip focus)
```

## Fail Backup
`backup/2026-06-16/map_view_screen copy.dart1.bak`
