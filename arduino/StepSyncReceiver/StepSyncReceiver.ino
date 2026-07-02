/*
  StepSync BLE Receiver
  Runs on an Arduino UNO R4 WiFi or any ArduinoBLE-compatible board.
  Acts as a BLE Peripheral (GATT server) that advertises the StepSync service.
  When the Garmin central device writes the daily step count, the sketch
  receives the 4-byte payload, decodes it as a 32-bit little-endian integer,
  prints the value to the Serial Monitor, and toggles the onboard LED.
*/

#include <ArduinoBLE.h>

// Service and Characteristic UUIDs matching the Garmin app GATT profile
const char* SERVICE_UUID = "329c2dc4-7fcc-47e0-b6df-20353df6efb3";
const char* CHARACTERISTIC_UUID = "b0a70198-d10c-4fa6-8ef3-d64e9a8f4c1d";

// Set up the BLE Service
BLEService stepService(SERVICE_UUID);

// Set up the Step Count characteristic (Write-enabled, 4-byte array)
BLECharacteristic stepCountChar(CHARACTERISTIC_UUID, BLEWrite | BLERead, 4);

const int ledPin = LED_BUILTIN; // Onboard LED to indicate sync activity

void setup() {
  Serial.begin(115200);
  while (!Serial); // Wait for Serial monitor to open

  pinMode(ledPin, OUTPUT);
  digitalWrite(ledPin, LOW);

  // Initialize BLE hardware
  if (!BLE.begin()) {
    Serial.println("Error: Starting BLE failed!");
    while (1);
  }

  // Set advertised local name and service
  BLE.setLocalName("StepSyncArduino");
  BLE.setAdvertisedService(stepService);

  // Add the characteristic to the service, and the service to the BLE stack
  stepService.addCharacteristic(stepCountChar);
  BLE.addService(stepService);

  // Start advertising
  BLE.advertise();

  Serial.println("StepSync BLE Receiver Active!");
  Serial.print("Advertising Name: StepSyncArduino\n");
  Serial.print("Service UUID: ");
  Serial.println(SERVICE_UUID);
  Serial.println("Waiting for Garmin central connection...");
}

void loop() {
  // Listen for BLE central devices to connect
  BLEDevice central = BLE.central();

  if (central) {
    Serial.print("Connected to central: ");
    Serial.println(central.address());

    // While the central is connected to peripheral
    while (central.connected()) {
      // Check if the characteristic was written by the central
      if (stepCountChar.written()) {
        const uint8_t* val = stepCountChar.value();
        int valLength = stepCountChar.valueLength();

        if (valLength == 4) {
          // Decode 4-byte little-endian payload to 32-bit unsigned integer
          uint32_t stepCount = 0;
          stepCount |= (uint32_t)val[0];
          stepCount |= (uint32_t)val[1] << 8;
          stepCount |= (uint32_t)val[2] << 16;
          stepCount |= (uint32_t)val[3] << 24;

          Serial.print("SUCCESS: Steps synced! Daily Step Count: ");
          Serial.println(stepCount);

          // Blink the onboard LED to signal successful sync
          digitalWrite(ledPin, HIGH);
          delay(500);
          digitalWrite(ledPin, LOW);
        } else {
          Serial.print("WARNING: Received invalid payload length: ");
          Serial.println(valLength);
        }
      }
    }

    // When the central disconnects
    Serial.print("Disconnected from central: ");
    Serial.println(central.address());
  }
}
