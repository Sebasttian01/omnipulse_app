import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

void main() {
  FlutterBluePlus.setLogLevel(LogLevel.none, color: false);
  runApp(const OhmMeterApp());
}

class OhmMeterApp extends StatelessWidget {
  const OhmMeterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Óhmetro IoT',
      theme: ThemeData.dark().copyWith(
        primaryColor: Colors.green,
        colorScheme: const ColorScheme.dark(
          primary: Colors.green,
          secondary: Colors.lightGreenAccent,
        ),
      ),
      home: const ScanScreen(),
    );
  }
}

// ==========================================
// PANTALLA 1: ESCÁNER DE DISPOSITIVOS BLE
// ==========================================
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> scanResults = [];
  bool isScanning = false;
  late StreamSubscription<List<ScanResult>> scanSub;

  @override
  void initState() {
    super.initState();
    scanSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() => scanResults = results);
    });
  }

  @override
  void dispose() {
    scanSub.cancel();
    super.dispose();
  }

  void startScan() async {
    setState(() => isScanning = true);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 5));
    await Future.delayed(const Duration(seconds: 5));
    setState(() => isScanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buscar ESP32')),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // ESPACIO RESERVADO PARA EL LOGO DE LA UIS
          Container(
            height: 100,
            width: 100,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('LOGO\nUIS', textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 20),

          // BOTÓN DE ESCÁNER REAL
          ElevatedButton.icon(
            onPressed: isScanning ? null : startScan,
            icon: isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bluetooth_searching),
            label: Text(isScanning ? 'Buscando...' : 'Buscar Dispositivos'),
          ),
          const SizedBox(height: 10),

          // NUEVO BOTÓN: PROBAR INTERFAZ SIN ESP32
          TextButton.icon(
            onPressed: () {
              // Navega a la pantalla 2 enviando un dispositivo nulo (Modo Simulación)
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DeviceScreen(device: null),
                ),
              );
            },
            icon: const Icon(Icons.phone_android, color: Colors.grey),
            label: const Text(
              'Probar Interfaz sin ESP32',
              style: TextStyle(color: Colors.grey),
            ),
          ),

          const Divider(height: 30),
          Expanded(
            child: ListView.builder(
              itemCount: scanResults.length,
              itemBuilder: (context, index) {
                final device = scanResults[index].device;
                return ListTile(
                  title: Text(
                    device.advName.isEmpty
                        ? 'Dispositivo Desconocido'
                        : device.advName,
                  ),
                  subtitle: Text(device.remoteId.toString()),
                  trailing: ElevatedButton(
                    child: const Text('Conectar'),
                    onPressed: () {
                      FlutterBluePlus.stopScan();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => DeviceScreen(device: device),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// PANTALLA 2: MEDICIÓN, TELEMETRÍA Y CONTROL
// ==========================================
class DeviceScreen extends StatefulWidget {
  // Ahora el dispositivo puede ser nulo para permitir el Modo Simulación
  final BluetoothDevice? device;
  const DeviceScreen({super.key, required this.device});

  @override
  State<DeviceScreen> createState() => _DeviceScreenState();
}

class _DeviceScreenState extends State<DeviceScreen> {
  final String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String charNotifyUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  final String charWriteUuid = "beb5483f-36e1-4688-b7f5-ea07361b26a8";

  BluetoothCharacteristic? notifyChar;
  BluetoothCharacteristic? writeChar;
  StreamSubscription? charSub;

  bool isConnected = false;
  bool isMeasuring = false;

  double resistanceValue = 0.0;
  int batteryLevel = 85; // Valor por defecto visual
  bool isCharging = true; // Valor por defecto visual
  int chargeTime = 30; // Valor por defecto visual

  List<String> history = [];

  @override
  void initState() {
    super.initState();
    // Solo intenta conectar si hay un dispositivo real enviado desde el escáner
    if (widget.device != null) {
      connectToDevice();
    }
  }

  void connectToDevice() async {
    try {
      await widget.device!.connect();
      setState(() => isConnected = true);
      discoverServices();
    } catch (e) {
      debugPrint("Error conectando: $e");
    }
  }

  void discoverServices() async {
    List<BluetoothService> services = await widget.device!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString() == serviceUuid) {
        for (var char in service.characteristics) {
          if (char.uuid.toString() == charNotifyUuid) {
            notifyChar = char;
            await notifyChar!.setNotifyValue(true);
            charSub = notifyChar!.onValueReceived.listen((value) {
              parseIncomingData(value);
            });
          }
          if (char.uuid.toString() == charWriteUuid) {
            writeChar = char;
          }
        }
      }
    }
  }

  void parseIncomingData(List<int> value) {
    if (value.isEmpty) return;
    String dataString = utf8.decode(value);
    List<String> parts = dataString.split(',');

    if (parts.length == 4) {
      setState(() {
        resistanceValue = double.tryParse(parts[0]) ?? 0.0;
        batteryLevel = int.tryParse(parts[1]) ?? 0;
        isCharging = (parts[2] == '1');
        chargeTime = int.tryParse(parts[3]) ?? 0;
      });

      if (isMeasuring) {
        String timestamp =
            "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
        history.insert(
          0,
          "[$timestamp] Medición: ${resistanceValue.toStringAsFixed(4)} Ω",
        );
      }
    }
  }

  void toggleMeasurement() async {
    setState(() {
      isMeasuring = !isMeasuring;
    });

    // Simulador visual si no hay ESP32 conectado
    if (widget.device == null || !isConnected) {
      if (isMeasuring) {
        // Agrega un dato de prueba al historial
        String timestamp =
            "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}";
        history.insert(0, "[$timestamp] Prueba UI: 0.4500 Ω");
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Modo Simulación: ESP32 no está conectado.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    // Código real si hay ESP32
    if (writeChar != null && isConnected) {
      String command = isMeasuring ? "1" : "0";
      await writeChar!.write(utf8.encode(command), withoutResponse: true);
    }
  }

  @override
  void dispose() {
    charSub?.cancel();
    widget.device?.disconnect(); // El ? evita errores si el device es null
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Determinar el título basado en si es simulación o dispositivo real
    String titleText = widget.device == null
        ? "Modo Simulación"
        : (widget.device!.advName.isEmpty
              ? "Dispositivo"
              : widget.device!.advName);

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                widget.device == null
                    ? "SIMULACIÓN"
                    : (isConnected ? "CONECTADO" : "CONECTANDO..."),
                style: TextStyle(
                  color: widget.device == null
                      ? Colors.blue
                      : (isConnected ? Colors.green : Colors.orange),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[850],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isCharging
                            ? Icons.battery_charging_full
                            : Icons.battery_std,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Batería: $batteryLevel%',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                  if (isCharging)
                    Text(
                      'Faltan: $chargeTime min',
                      style: const TextStyle(color: Colors.greenAccent),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            const Text(
              'RESISTENCIA',
              style: TextStyle(letterSpacing: 2, color: Colors.grey),
            ),
            Text(
              '${resistanceValue.toStringAsFixed(4)} Ω',
              style: const TextStyle(
                fontSize: 56,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isMeasuring ? Colors.red : Colors.green,
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: 15,
                ),
              ),
              onPressed: toggleMeasurement,
              icon: Icon(
                isMeasuring ? Icons.stop : Icons.play_arrow,
                color: Colors.black,
              ),
              label: Text(
                isMeasuring ? 'DETENER MEDICIÓN' : 'INICIAR MEDICIÓN',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 30),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'HISTORIAL',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: history.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(Icons.history, color: Colors.green),
                    title: Text(history[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
