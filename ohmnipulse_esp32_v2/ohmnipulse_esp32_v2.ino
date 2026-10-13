#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// =========================================================================
// Miliohmímetro BLE para ESP32 - Optimizado (Batería y Promediado)
// =========================================================================

// --- Pines y Hardware ---
const int pwmPin = 18;           
const int pwmFrecuencia = 100; 
const int pwmResolucion = 8;     
const int pinADC = 34;           

// --- Constantes del Circuito ---
const float corrienteInyectada = 0.0196; 
const float gananciaAD620 = 50.4;         
const float voltajeReferenciaADC = 3.3;  

// --- Variables BLE y Estados ---
BLEServer *pServer = NULL;
BLECharacteristic *pCharacteristicTX = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;
bool medirYEnviar = false; 

// --- NUEVAS VARIABLES DE CONTROL (Ahorro y Promedios) ---
bool hardwareEncendido = false; 
int contadorMediciones = 0;
float sumaResistencias = 0.0;

#define SERVICE_UUID           "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID_TX "beb5483e-36e1-4688-b7f5-ea07361b26a8" 
#define CHARACTERISTIC_UUID_RX "beb5483f-36e1-4688-b7f5-ea07361b26a8" 

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("¡Celular Conectado!");
    };
    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      medirYEnviar = false; 
      Serial.println("Celular Desconectado.");
    }
};

class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) {
        if (rxValue[0] == '1') {
          medirYEnviar = true;
          Serial.println("=> APP: INICIAR MEDICIÓN");
        } else if (rxValue[0] == '0') {
          medirYEnviar = false;
          Serial.println("=> APP: DETENER MEDICIÓN");
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  
  // Configuramos el PWM pero lo dejamos APAGADO (Duty Cycle 0)
  ledcAttach(pwmPin, pwmFrecuencia, pwmResolucion);
  ledcWrite(pwmPin, 0); 
  hardwareEncendido = false;

  BLEDevice::init("ESP32_Miliohmimetro"); 
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristicTX = pService->createCharacteristic(
                        CHARACTERISTIC_UUID_TX,
                        BLECharacteristic::PROPERTY_NOTIFY
                      );
  pCharacteristicTX->addDescriptor(new BLE2902());

  BLECharacteristic *pCharacteristicRX = pService->createCharacteristic(
                                           CHARACTERISTIC_UUID_RX,
                                           BLECharacteristic::PROPERTY_WRITE
                                         );
  pCharacteristicRX->setCallbacks(new MyCallbacks());

  pService->start();
  pServer->getAdvertising()->start();
  Serial.println("BLE Activo. Circuito en reposo ahorrando batería.");
}

void loop() {
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); 
      pServer->startAdvertising(); 
      oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
      oldDeviceConnected = deviceConnected;
  }

  // LÓGICA DE MEDICIÓN Y ESTADOS
  if (deviceConnected && medirYEnviar) {
    
    // 1. Si el hardware estaba apagado, lo despertamos
    if (!hardwareEncendido) {
      Serial.println("Despertando circuito... estabilizando capacitores (-7V).");
      ledcWrite(pwmPin, 127); // Encender bomba de carga
      delay(1000);            // Esperar 1 segundo vital para la estabilidad
      hardwareEncendido = true;
      contadorMediciones = 0; // Reiniciamos variables
      sumaResistencias = 0.0;
    }

    // 2. Toma de una lectura con oversampling
    long sumaLecturas = 0;
    int muestras = 500;
    for(int i = 0; i < muestras; i++){
      sumaLecturas += analogRead(pinADC);
      delayMicroseconds(50);
    }
    float promedioADC = sumaLecturas / (float)muestras;

    float voltajeLeido = ((promedioADC * voltajeReferenciaADC) / 4095.0);
    float voltajeCalibrado = (voltajeLeido * 1.0) + 0.100; // offsetVoltaje

    // 3. Evaluar y promediar
    if (voltajeCalibrado > 3.0) {
      // Si está abierto, enviamos 0 inmediatamente y reseteamos el buffer
      // para no promediar "aire" con lecturas reales.
      Serial.println("Circuito Abierto");
      contadorMediciones = 0;
      sumaResistencias = 0.0;
      pCharacteristicTX->setValue("0.00,85,1,30");
      pCharacteristicTX->notify();
    } 
    else {
      float voltajeReal = (voltajeCalibrado / gananciaAD620);
      float resistenciaBase = voltajeReal / corrienteInyectada;
      float resistenciaFinalOhmios = (resistenciaBase * 1.036);
      float resistenciamOhm = resistenciaFinalOhmios * 1000.0;
      
      sumaResistencias += resistenciamOhm;
      contadorMediciones++;
      
      Serial.print("Muestra ");
      Serial.print(contadorMediciones);
      Serial.print("/5: ");
      Serial.print(resistenciamOhm, 2);
      Serial.println(" mΩ");

      // 4. Cuando llegamos a 5 muestras, enviamos a la App
      if (contadorMediciones >= 50) {
        float promedioFinal = sumaResistencias / 50.0;
        
        Serial.print(">> ENVIANDO PROMEDIO BLE: ");
        Serial.print(promedioFinal, 2);
        Serial.println(" mΩ");

        String datosBLE = String(promedioFinal, 2) + ",85,1,30";
        pCharacteristicTX->setValue(datosBLE.c_str());
        pCharacteristicTX->notify();
        
        // Reiniciamos para el próximo bloque de 5
        contadorMediciones = 0;
        sumaResistencias = 0.0;
      }
    }
  } 
  else {
    // 5. MODO REPOSO (Bajo consumo)
    if (hardwareEncendido) {
      Serial.println("Modo Reposo: Apagando hardware analógico...");
      ledcWrite(pwmPin, 0); // Apaga el transistor y los Op-Amps
      hardwareEncendido = false;
    }
    // Retardo largo en reposo para descargar el procesador
    delay(300);
  }
}