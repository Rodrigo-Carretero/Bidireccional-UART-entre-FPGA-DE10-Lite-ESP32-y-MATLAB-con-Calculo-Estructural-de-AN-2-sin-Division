// ESP32 DEVKIT V1 (ESP32 clasico): puente USB-UART2 transparente
// MATLAB <--> USB Serial <--> ESP32 <--> UART2 <--> DE10-Lite
// ESP32 NO calcula la potencia ni modifica datos.
#include <Arduino.h>

static const int ESP32_RX2 = 16; // RX2 conectado al UART_TX de FPGA, JP1-2
static const int ESP32_TX2 = 17; // TX2 conectado al UART_RX de FPGA, JP1-1
static const uint32_t BAUD = 9600;

void setup() {
    Serial.begin(BAUD);                     // USB -> MATLAB
    Serial2.begin(BAUD, SERIAL_8N1, ESP32_RX2, ESP32_TX2); // -> FPGA
    // No usar Serial.print ni println: contaminaria el protocolo binario.
}

void loop() {
    // Entradas desde MATLAB: byte A, n decimal ASCII y LF.
    while (Serial.available() > 0) {
        Serial2.write(static_cast<uint8_t>(Serial.read()));
    }
    // FPGA devuelve status + cuatro bytes; reenvio transparente.
    while (Serial2.available() > 0) {
        Serial.write(static_cast<uint8_t>(Serial2.read()));
    }
}
