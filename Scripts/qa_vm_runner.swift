import Darwin
import Foundation
import Virtualization

// Runs the already-provisioned, owned UTM guest without a host window or input view.
// Guest Screen Sharing supplies the display; clipboard sharing remains absent.
func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}

let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Primary Paste QA")
let manifestURL = root.appendingPathComponent("manifest.json")
guard CommandLine.arguments.count == 1,
    root.resolvingSymlinksInPath() == root,
    let manifestData = try? Data(contentsOf: manifestURL),
    let manifest = (try? JSONSerialization.jsonObject(with: manifestData)) as? [String: Any],
    manifest["owner"] as? String == "primary-paste-qa", manifest["schema"] as? Int == 1,
    manifest["root"] as? String == root.path,
    let vmPath = manifest["vmPath"] as? String, let uuid = manifest["vmUUID"] as? String
else { fail("Missing owned QA environment; no VM was started") }
let package = URL(fileURLWithPath: vmPath)
guard package.deletingLastPathComponent() == root.appendingPathComponent("VM"),
    package.resolvingSymlinksInPath() == package
else { fail("Guest package must remain inside the owned environment") }
let configURL = package.appendingPathComponent("config.plist")
guard configURL.resolvingSymlinksInPath() == configURL,
    let data = try? Data(contentsOf: configURL),
    let settings = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
    settings["Backend"] as? String == "Apple",
    (settings["Information"] as? [String: Any])?["UUID"] as? String == uuid,
    let virtualization = settings["Virtualization"] as? [String: Any],
    virtualization["ClipboardSharing"] as? Bool == false,
    let system = settings["System"] as? [String: Any],
    let mac = system["MacPlatform"] as? [String: Any],
    let hardware = mac["HardwareModel"] as? Data,
    let machine = mac["MachineIdentifier"] as? Data,
    let auxiliary = mac["AuxiliaryStoragePath"] as? String,
    let drives = settings["Drive"] as? [[String: Any]], drives.count == 1,
    let image = drives[0]["ImageName"] as? String,
    let networks = settings["Network"] as? [[String: Any]], networks.count == 1,
    networks[0]["Mode"] as? String == "Shared",
    let address = networks[0]["MacAddress"] as? String,
    let cpuCount = system["CPUCount"] as? Int, let memoryMiB = system["MemorySize"] as? UInt64
else { fail("Unsupported or unsafe owned VM configuration") }

func storage(_ name: String) -> URL {
    let directory = package.appendingPathComponent("Data")
    let url = directory.appendingPathComponent(name)
    guard !name.isEmpty, name == url.lastPathComponent,
        directory.resolvingSymlinksInPath() == directory, url.resolvingSymlinksInPath() == url
    else { fail("Guest storage must not escape its package") }
    return url
}
let lockURL = root.appendingPathComponent("runner.lock")
guard lockURL.resolvingSymlinksInPath() == lockURL else { fail("Unsafe runner lock") }
let lock = open(lockURL.path, O_RDWR | O_CREAT | O_NOFOLLOW, 0o600)
guard lock >= 0, flock(lock, LOCK_EX | LOCK_NB) == 0 else { fail("The guest runner is already active") }

let stateURL = root.appendingPathComponent("runner-state.json")
guard stateURL.resolvingSymlinksInPath() == stateURL else { fail("Unsafe runner state") }
final class StateWriter {
    let uuid: String
    let url: URL
    init(uuid: String, url: URL) { self.uuid = uuid; self.url = url }
    func write(_ state: String) {
        let record: [String: Any] = ["owner": "primary-paste-qa", "uuid": uuid, "pid": getpid(), "state": state]
        if let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
let writer = StateWriter(uuid: uuid, url: stateURL)

let config = VZVirtualMachineConfiguration()
let platform = VZMacPlatformConfiguration()
guard let model = VZMacHardwareModel(dataRepresentation: hardware), model.isSupported,
    let identifier = VZMacMachineIdentifier(dataRepresentation: machine),
    let macAddress = VZMACAddress(string: address)
else { fail("Guest platform identity is unsupported") }
platform.hardwareModel = model
platform.machineIdentifier = identifier
platform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: storage(auxiliary))
config.platform = platform
config.bootLoader = VZMacOSBootLoader()
config.cpuCount = cpuCount
config.memorySize = memoryMiB * 1024 * 1024
let disk = try VZDiskImageStorageDeviceAttachment(url: storage(image), readOnly: false)
config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: disk)]
let network = VZVirtioNetworkDeviceConfiguration()
network.macAddress = macAddress
network.attachment = VZNATNetworkDeviceAttachment()
config.networkDevices = [network]
let graphics = VZMacGraphicsDeviceConfiguration()
graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: 1280, heightInPixels: 800, pixelsPerInch: 80)]
config.graphicsDevices = [graphics]
config.keyboards = [VZMacKeyboardConfiguration()]
config.pointingDevices = [VZMacTrackpadConfiguration()]
config.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
config.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]
let shareURL = root.appendingPathComponent("Share")
guard shareURL.resolvingSymlinksInPath() == shareURL else { fail("Unsafe guest share") }
let directory = VZVirtioFileSystemDeviceConfiguration(tag: "share")
directory.share = VZSingleDirectoryShare(directory: VZSharedDirectory(url: shareURL, readOnly: true))
config.directorySharingDevices = [directory]
try config.validate()

final class GuestDelegate: NSObject, VZVirtualMachineDelegate {
    let writer: StateWriter
    init(writer: StateWriter) { self.writer = writer }
    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        writer.write("stopped")
        exit(0)
    }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        writer.write("failed")
        fail("Guest stopped with error: \(error.localizedDescription)")
    }
}
let delegate = GuestDelegate(writer: writer)
let vm = VZVirtualMachine(configuration: config)
vm.delegate = delegate
// SIGTERM requests orderly guest shutdown. It never force-stops the machine.
signal(SIGTERM, SIG_IGN)
signal(SIGINT, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termination.setEventHandler {
    if vm.canRequestStop { try? vm.requestStop() }
}
termination.resume()
writer.write("starting")
vm.start { result in
    switch result {
    case .success:
        writer.write("started")
        print("Owned guest started without a host window")
        fflush(stdout)
    case .failure(let error):
        writer.write("failed")
        fail("Guest could not start: \(error.localizedDescription)")
    }
}
RunLoop.main.run()
