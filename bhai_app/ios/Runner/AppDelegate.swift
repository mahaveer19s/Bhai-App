import UIKit
import Flutter
import CoreBluetooth

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate, CBCentralManagerDelegate, CBPeripheralManagerDelegate {
  private let methodChannelName = "com.bhai.app/ble_emergency"
  private let eventChannelName = "com.bhai.app/ble_emergency_events"
  private let serviceUuid = CBUUID(string: "7c3e4eae-a1ae-4f7d-b6f2-9a110a11a001")

  private var centralManager: CBCentralManager?
  private var peripheralManager: CBPeripheralManager?
  private var eventSink: FlutterEventSink?
  private var activeType: Int = 1
  private var activeSenderId: String = "00000000"
  private var activeTargetId: String = "00000000"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    
    let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: controller.binaryMessenger)
    eventChannel.setStreamHandler(BLEStreamHandler(delegate: self))

    let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: controller.binaryMessenger)
    methodChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      self?.handleBleCall(call: call, result: result)
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  fileprivate func setEventSink(_ sink: FlutterEventSink?) {
    self.eventSink = sink
  }

  private func handleBleCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isBluetoothEnabled":
      if centralManager == nil {
        centralManager = CBCentralManager(delegate: self, queue: nil)
      }
      result(centralManager?.state == .poweredOn)
    case "requestEnableBluetooth":
      result(true)
    case "startAdvertising":
      let args = call.arguments as? [String: Any]
      let type = args?["type"] as? Int ?? 1
      let senderId = args?["senderId"] as? String ?? "00000000"
      let targetId = args?["targetId"] as? String ?? "00000000"
      startAdvertising(type: type, senderId: senderId, targetId: targetId, result: result)
    case "stopAdvertising":
      stopAdvertising()
      result(nil)
    case "startScanning":
      startScanning(result: result)
    case "stopScanning":
      stopScanning()
      result(nil)
    case "dialEmergency":
      let args = call.arguments as? [String: Any]
      let number = args?["number"] as? String ?? "112"
      if let url = URL(string: "tel:\(number)"), UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func startAdvertising(type: Int, senderId: String, targetId: String, result: @escaping FlutterResult) {
    self.activeType = type
    self.activeSenderId = senderId
    self.activeTargetId = targetId

    if peripheralManager == nil {
      peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
    } else if peripheralManager?.state == .poweredOn {
      let localName = "BHAI-\(type)-\(senderId)-\(targetId)"
      let advertisementData: [String: Any] = [
        CBAdvertisementDataServiceUUIDsKey: [serviceUuid],
        CBAdvertisementDataLocalNameKey: localName
      ]
      peripheralManager?.stopAdvertising()
      peripheralManager?.startAdvertising(advertisementData)
    }
    result(nil)
  }

  private func stopAdvertising() {
    peripheralManager?.stopAdvertising()
  }

  private func startScanning(result: @escaping FlutterResult) {
    if centralManager == nil {
      centralManager = CBCentralManager(delegate: self, queue: nil)
    } else if centralManager?.state == .poweredOn {
      centralManager?.scanForPeripherals(withServices: [serviceUuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
    result(nil)
  }

  private func stopScanning() {
    centralManager?.stopScan()
  }

  // MARK: - CBCentralManagerDelegate
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    if central.state == .poweredOn {
      central.scanForPeripherals(withServices: [serviceUuid], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }
  }

  func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
    let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
    if localName.hasPrefix("BHAI-") {
      let parts = localName.split(separator: "-")
      let type = parts.count > 1 ? Int(parts[1]) ?? 1 : 1
      let senderId = parts.count > 2 ? String(parts[2]) : "UNKNOWN"
      let targetId = parts.count > 3 ? String(parts[3]) : "00000000"

      let now = Date().timeIntervalSince1970
      eventSink?([
        "type": type,
        "senderId": senderId,
        "targetId": targetId,
        "rssi": RSSI.intValue,
        "detectedAt": Int64(now * 1000)
      ])
    }
  }

  // MARK: - CBPeripheralManagerDelegate
  func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
    if peripheral.state == .poweredOn {
      let localName = "BHAI-\(activeType)-\(activeSenderId)-\(activeTargetId)"
      let advertisementData: [String: Any] = [
        CBAdvertisementDataServiceUUIDsKey: [serviceUuid],
        CBAdvertisementDataLocalNameKey: localName
      ]
      peripheral.stopAdvertising()
      peripheral.startAdvertising(advertisementData)
    }
  }
}

private class BLEStreamHandler: NSObject, FlutterStreamHandler {
  private weak var delegate: AppDelegate?

  init(delegate: AppDelegate) {
    self.delegate = delegate
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    delegate?.setEventSink(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    delegate?.setEventSink(nil)
    return nil
  }
}
