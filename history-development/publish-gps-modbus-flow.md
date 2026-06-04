# Alur publish MQTT: GPS-change vs polling Modbus

Dokumen rujukan (keputusan projek). Kod: `PublishService`, `ModbusTransmissionScreen`, `HomeScreen`.

## Prinsip

1. **MQTT sentiasa dihantar** — sama ada sumber ialah polling Modbus atau perubahan GPS (GPS-change).
2. **GPS-change di-hold** hanya semasa **event polling aktif** (start loop → stop loop).
3. **Selepas stop polling**, walaupun masih di skrin Transmit, **publish GPS-change dibenarkan semula**.
4. Semasa setiap publish polling: utamakan lat/lon terkini; jika GPS “stuck” atau tiada fix baru, guna **last known** fix.

## Jadual tingkah laku

| Konteks | Polling | Publish GPS-change | Publish Modbus + lat/lon |
|---------|---------|--------------------|---------------------------|
| Home | — | Ya (throttle koordinat) | Tidak |
| Transmit (idle) | Stop | Ya | Hanya jika ada RX manual (bukan loop) |
| Transmit | Start (loop) | **Hold** | Ya, setiap respons poll |
| Keluar Transmit | — | Ya (Home) | `publishExitSnapshot` (`status_live`: offline) |

## Hook kod

| Peristiwa | Lokasi | Tindakan |
|-----------|--------|----------|
| Masuk skrin Transmit | `initState` | `setTransmissionScreenActive(true)`, `LocationService().start()` |
| Start polling | `onStartLoop` | `pauseGps()` |
| Stop polling | `onStopLoop` / putus sambungan | `resumeGps()` |
| Keluar skrin Transmit | `dispose` | `publishExitSnapshot`, `setTransmissionScreenActive(false)`, `resumeGps()` jika perlu |

## Lat/lon untuk `publishModbus`

1. Guna `LocationService.lastFix` (stream).
2. Jika tiada, cuba `getCurrentFix` (timeout pendek).
3. Jika masih tiada tetapi pernah ada fix untuk Modbus, guna **cache last reliable** (`PublishService`).

## Semak regresi

- [ ] Home: pergerakan GPS → MQTT dengan `sensor_data = [-1]`.
- [ ] Transmit tanpa poll: GPS-change masih publish.
- [ ] Transmit + start poll: GPS-change berhenti; setiap RX → MQTT dengan sensor.
- [ ] Stop poll di Transmit: GPS-change sambung semula.
- [ ] Keluar Transmit semasa poll: exit snapshot + GPS tidak kekal pause.

Terakhir dikemas kini: 2026-06-04
