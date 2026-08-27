#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

static const char *DEVICE_NAME = "sheRuntime-StopWatch";

static const char *SERVICE_UUID =
    "a7f00001-4d7a-4e6b-9f30-6a8e2a14c001";
static const char *COMMAND_CHARACTERISTIC_UUID =
    "a7f00002-4d7a-4e6b-9f30-6a8e2a14c001";
static const char *RESPONSE_CHARACTERISTIC_UUID =
    "a7f00003-4d7a-4e6b-9f30-6a8e2a14c001";

static BLECharacteristic *responseCharacteristic = nullptr;

static void startAdvertising() {
    BLEDevice::startAdvertising();
    Serial.println("BLE advertising started.");
}

class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer *server) override {
        Serial.println("BLE client connected.");
    }

    void onDisconnect(BLEServer *server) override {
        Serial.println("BLE client disconnected.");
        startAdvertising();
        Serial.println("BLE advertising restored after disconnect.");
    }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *characteristic) override {
        const std::string command = characteristic->getValue();
        Serial.print("BLE command received: ");
        Serial.println(command.c_str());

        if (command == "ping") {
            responseCharacteristic->setValue("pong");
            responseCharacteristic->notify();
            Serial.println("BLE response notified: pong");
        } else {
            Serial.println("BLE command ignored (expected ping).");
        }
    }
};

static void initializeBLE() {
    BLEDevice::init(DEVICE_NAME);

    BLEServer *server = BLEDevice::createServer();
    server->setCallbacks(new ServerCallbacks());

    BLEService *service = server->createService(SERVICE_UUID);

    BLECharacteristic *commandCharacteristic = service->createCharacteristic(
        COMMAND_CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_WRITE
    );
    commandCharacteristic->setCallbacks(new CommandCallbacks());

    responseCharacteristic = service->createCharacteristic(
        RESPONSE_CHARACTERISTIC_UUID,
        BLECharacteristic::PROPERTY_NOTIFY
    );
    responseCharacteristic->addDescriptor(new BLE2902());

    service->start();
    BLEAdvertising *advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->setScanResponse(true);
    startAdvertising();
}

void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println();
    Serial.println("Starting BLE probe...");

    initializeBLE();
    Serial.print("Device name: ");
    Serial.println(DEVICE_NAME);
    Serial.print("Service UUID: ");
    Serial.println(SERVICE_UUID);
}

void loop() {
    delay(1000);
}
