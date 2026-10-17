import AudioToolbox
import CoreAudio
import KoeTypeCore

/// Lists the Mac's audio input devices.
enum AudioDevices {
    /// One serial queue for listings requested by the UI: the HAL call can stall, and it must hold
    /// neither the main queue nor a thread of the cooperative pool while it does.
    private static let listingQueue = DispatchQueue(label: "jp.caruvistar.koetype.audio-devices")
    private static let listingLock = NSLock()
    /// Callers waiting for the listing in flight; a request made while one is outstanding shares it.
    private static var listingWaiters: [@Sendable ([AudioInputDevice]) -> Void] = []   // guarded by `listingLock`
    private static let maxListingWaiters = 8

    /// The input devices, listed off the caller's thread, or nil when the listing has not returned within
    /// `seconds`. While a listing is still waiting on the HAL, further requests do not pile up: they share
    /// that listing's result once it returns. Each caller's own wait is bounded all the same, so a stuck
    /// HAL fails every caller in time instead of holding them (the late result is simply dropped).
    static func inputDevices(within seconds: TimeInterval) async -> [AudioInputDevice]? {
        await Deadline.first(within: seconds) { deliver in
            let first: Bool = listingLock.withLock {
                // While the HAL never returns, every caller times out on its own; the oldest waiters are
                // the ones whose deadline has long passed, so the list is kept short by dropping them.
                if listingWaiters.count >= maxListingWaiters { listingWaiters.removeFirst() }
                listingWaiters.append(deliver)
                return listingWaiters.count == 1
            }
            guard first else { return }
            listingQueue.async {
                let devices = inputs().map(\.device)
                let waiters: [@Sendable ([AudioInputDevice]) -> Void] = listingLock.withLock {
                    defer { listingWaiters.removeAll() }
                    return listingWaiters
                }
                for waiter in waiters { waiter(devices) }
            }
        }
    }

    static func inputs() -> [(device: AudioInputDevice, id: AudioDeviceID)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap { id in
            guard hasInput(id), let uid = string(id, kAudioDevicePropertyDeviceUID),
                  let name = string(id, kAudioObjectPropertyName) else { return nil }
            return (AudioInputDevice(uid: uid, name: name, isBuiltIn: transport(id) == kAudioDeviceTransportTypeBuiltIn), id)
        }
    }

    /// The Core Audio device to record from for this preference, or nil for the system default.
    static func deviceID(for preference: MicrophonePreference) -> AudioDeviceID? {
        let all = inputs()
        guard let wanted = preference.resolve(among: all.map(\.device)) else { return nil }
        return all.first { $0.device.uid == wanted.uid }?.id
    }

    /// The device a recording with this preference uses right now: the chosen one, else the system default.
    static func inputDeviceID(for preference: MicrophonePreference) -> AudioDeviceID? {
        if let chosen = deviceID(for: preference) { return chosen }
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// UID of the microphone a recording with this preference uses right now, nil if there is no input.
    static func inputUID(for preference: MicrophonePreference) -> String? {
        inputDeviceID(for: preference).flatMap { string($0, kAudioDevicePropertyDeviceUID) }
    }

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func transport(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
