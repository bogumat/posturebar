import CoreAudio
import Foundation

/// A conservative call guard. If any process is actively reading audio input,
/// posture capture yields the camera. This intentionally favors calls and may
/// also pause for dictation or audio-recording apps.
final class MicrophoneActivityMonitor {
    var onChange: ((Bool) -> Void)?

    private let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var processListListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var legacyInputListener: AudioObjectPropertyListenerBlock?
    private var legacyInputDevice = kAudioObjectUnknown
    private var lastValue: Bool?

    func start() {
        stop()

        var processListAddress = Self.processListAddress
        guard AudioObjectHasProperty(systemObject, &processListAddress) else {
            startLegacyDeviceMonitoring()
            return
        }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.synchronizeProcessListeners()
            self?.publishCurrentValue()
        }
        guard AudioObjectAddPropertyListenerBlock(
            systemObject,
            &processListAddress,
            .main,
            listener
        ) == noErr else {
            startLegacyDeviceMonitoring()
            return
        }

        processListListener = listener
        synchronizeProcessListeners()
        publishCurrentValue()
    }

    func stop() {
        if let processListListener {
            var address = Self.processListAddress
            AudioObjectRemovePropertyListenerBlock(
                systemObject,
                &address,
                .main,
                processListListener
            )
        }
        processListListener = nil

        for (processID, listener) in processListeners {
            var address = Self.runningInputAddress
            AudioObjectRemovePropertyListenerBlock(
                processID,
                &address,
                .main,
                listener
            )
        }
        processListeners.removeAll(keepingCapacity: false)

        if let defaultInputListener {
            var address = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(
                systemObject,
                &address,
                .main,
                defaultInputListener
            )
        }
        defaultInputListener = nil
        removeLegacyInputListener()
        lastValue = nil
    }

    private func publishCurrentValue() {
        let currentValue = Self.isAnyProcessCapturingAudioInput()
        guard currentValue != lastValue else { return }
        lastValue = currentValue
        onChange?(currentValue)
    }

    private func synchronizeProcessListeners() {
        var listAddress = Self.processListAddress
        guard let currentProcessIDs = Self.objectIDArray(
            object: systemObject,
            address: &listAddress
        ) else {
            return
        }

        let currentIDs = Set(currentProcessIDs)
        let removedIDs = Set(processListeners.keys).subtracting(currentIDs)
        for processID in removedIDs {
            guard let listener = processListeners.removeValue(forKey: processID) else {
                continue
            }
            var address = Self.runningInputAddress
            AudioObjectRemovePropertyListenerBlock(
                processID,
                &address,
                .main,
                listener
            )
        }

        let addedIDs = currentIDs.subtracting(processListeners.keys)
        for processID in addedIDs {
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.publishCurrentValue()
            }
            var address = Self.runningInputAddress
            if AudioObjectAddPropertyListenerBlock(
                processID,
                &address,
                .main,
                listener
            ) == noErr {
                processListeners[processID] = listener
            }
        }
    }

    private func startLegacyDeviceMonitoring() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.synchronizeLegacyInputListener()
            self?.publishCurrentValue()
        }
        var address = Self.defaultInputAddress
        if AudioObjectAddPropertyListenerBlock(
            systemObject,
            &address,
            .main,
            listener
        ) == noErr {
            defaultInputListener = listener
        }

        synchronizeLegacyInputListener()
        publishCurrentValue()
    }

    private func synchronizeLegacyInputListener() {
        var defaultInputAddress = Self.defaultInputAddress
        let inputDevice = Self.audioObjectIDValue(
            object: systemObject,
            address: &defaultInputAddress
        ) ?? kAudioObjectUnknown
        guard inputDevice != legacyInputDevice else { return }

        removeLegacyInputListener()
        guard inputDevice != kAudioObjectUnknown else { return }

        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.publishCurrentValue()
        }
        var runningAddress = Self.legacyRunningInputAddress
        guard AudioObjectHasProperty(inputDevice, &runningAddress),
              AudioObjectAddPropertyListenerBlock(
                  inputDevice,
                  &runningAddress,
                  .main,
                  listener
              ) == noErr else {
            return
        }

        legacyInputDevice = inputDevice
        legacyInputListener = listener
    }

    private func removeLegacyInputListener() {
        if let legacyInputListener, legacyInputDevice != kAudioObjectUnknown {
            var address = Self.legacyRunningInputAddress
            AudioObjectRemovePropertyListenerBlock(
                legacyInputDevice,
                &address,
                .main,
                legacyInputListener
            )
        }
        legacyInputListener = nil
        legacyInputDevice = kAudioObjectUnknown
    }

    private static var processListAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var runningInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var legacyRunningInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    static func isAnyProcessCapturingAudioInput() -> Bool {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var processListAddress = Self.processListAddress

        if AudioObjectHasProperty(systemObject, &processListAddress),
           let processIDs = objectIDArray(
               object: systemObject,
               address: &processListAddress
            ) {
            for processID in processIDs {
                var runningInputAddress = Self.runningInputAddress
                if uint32Value(object: processID, address: &runningInputAddress) == 1 {
                    return true
                }
            }
            return false
        }

        // Compatibility fallback for systems without Audio Process objects.
        var defaultInputAddress = Self.defaultInputAddress
        guard let inputDevice = audioObjectIDValue(
            object: systemObject,
            address: &defaultInputAddress
        ), inputDevice != kAudioObjectUnknown else {
            return false
        }

        var runningAddress = Self.legacyRunningInputAddress
        return uint32Value(object: inputDevice, address: &runningAddress) == 1
    }

    private static func objectIDArray(
        object: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> [AudioObjectID]? {
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return nil
        }

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        var values = [AudioObjectID](repeating: 0, count: count)
        let status = values.withUnsafeMutableBytes { bytes in
            AudioObjectGetPropertyData(
                object,
                &address,
                0,
                nil,
                &dataSize,
                bytes.baseAddress!
            )
        }
        return status == noErr ? values : nil
    }

    private static func uint32Value(
        object: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> UInt32? {
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            object,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }

    private static func audioObjectIDValue(
        object: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> AudioObjectID? {
        var value = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            object,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        return status == noErr ? value : nil
    }
}
