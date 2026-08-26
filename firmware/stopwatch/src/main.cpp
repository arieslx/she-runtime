#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>

static const char *DEVICE_NAME = "sheRuntime-StopWatch";

static const char *SERVICE_UUID =
    "a7f00001-4d7a-4e6b-9f30-6a8e2a14c001";

void setup() {
    Serial.begin(115200);
    delay(1000);

    Serial.println();
    Serial.println("Starting BLE probe...");

    // 初始化 BLE，并设置设备广播名称
    BLEDevice::init(DEVICE_NAME);

    // 创建 BLE GATT 服务端
    BLEServer *server = BLEDevice::createServer();

    // 创建我们自己的 sheRuntime 服务
    BLEService *service = server->createService(SERVICE_UUID);

    // 启动服务
    service->start();

    // 配置广播
    BLEAdvertising *advertising = BLEDevice::getAdvertising();
    advertising->addServiceUUID(SERVICE_UUID);
    advertising->setScanResponse(true);

    // 开始广播
    BLEDevice::startAdvertising();

    Serial.println("BLE advertising started.");
    Serial.println("Device name: sheRuntime-StopWatch");
}

void loop() {
    delay(1000);
}