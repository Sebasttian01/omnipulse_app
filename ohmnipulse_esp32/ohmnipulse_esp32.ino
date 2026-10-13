// =========================================================================
// Generador de Voltaje Negativo (Bomba de Carga) para ESP32 Core v3.x
// =========================================================================

const int pwmPin = 18;           // Pin conectado a la base del E13007F2 (con resistencia)
const int pwmFrecuencia = 100; // 50 kHz
const int pwmResolucion = 8;     // Resolución de 8 bits (valores de 0 a 255)
const int pinADC = 34; // Pin donde para conectar la salida protegida del AD620

// --- Constantes del Circuito ---
const float corrienteInyectada = 0.0196; // 19.6 mA en Amperios
const float gananciaAD620 = 50.4;         // Ganancia actual (sin trimmer)
const float voltajeReferenciaADC = 3.3;  // Voltaje de referencia del ESP32

void setup() {
  Serial.begin(115200);
  Serial.println("Iniciando generador de voltaje negativo...");

  // Nueva sintaxis simplificada para ESP32 Core 3.0.0+
  // Configura y asigna el pin en una sola línea
  ledcAttach(pwmPin, pwmFrecuencia, pwmResolucion);
  
  // Inicia la señal al 50% de Duty Cycle (127 es la mitad de 255)
  ledcWrite(pwmPin, 127);

  Serial.println("PWM activo.");
  Serial.println("Iniciando Miliohmímetro...");
}

void loop() {
  // 1. Sobremuestreo (Oversampling) para eliminar ruido
  long sumaLecturas = 0;
  int muestras = 500;

  for(int i = 0; i < muestras; i++){
    sumaLecturas += analogRead(pinADC);
    delayMicroseconds(50);
  }
    
  float promedioADC = sumaLecturas / (float)muestras;
  // 2. Convertir a Voltaje con CALIBRACIÓN
  // Multiplicamos por 1.051 para corregir el error interno del ESP32
  float factorCalibracion = 1.090; 
  float voltajeLeido = ((promedioADC * voltajeReferenciaADC) / 4095.0);

  float factorPendiente = 1.0;
  float offsetVoltaje = 0.100;

  float voltajeCalibrado = (voltajeLeido*factorPendiente) + offsetVoltaje;

  // 4. Aplicar la Ley de Ohm para calcular la resistencia
  // Quitamos el efecto de la ganancia para saber la caída de voltaje real en el componente

  if (voltajeCalibrado > 3.0){
    Serial.print("Voltaje Pin: ");
    Serial.print(voltajeCalibrado, 3);
    Serial.println("V | Resistencia: ---CIRCUITO ABIERTO ---");
  }
  else{
    float voltajeReal = (voltajeCalibrado / gananciaAD620);
    float voltajeRealmV = voltajeCalibrado*1000;
    // R = V / I
    float resistencia = voltajeReal / corrienteInyectada;
    float resistenciaCalibrada = (resistencia*1.036);
    float resistenciamOhm = resistenciaCalibrada*1000;

    // 5. Imprimir los resultados en pantalla
    Serial.print(" | Voltaje Pin: ");
    Serial.print(voltajeRealmV, 3);
    Serial.print(" mV | Resistencia calculada: ");
    Serial.print(resistenciaCalibrada, 2);
    Serial.print(" Ω");
    Serial.print(" Resistencia calculada: ");
    Serial.print(resistenciamOhm, 2);
    Serial.println(" mΩ");

  }
  // Esperar medio segundo antes de la siguiente lectura
  delay(500);
}