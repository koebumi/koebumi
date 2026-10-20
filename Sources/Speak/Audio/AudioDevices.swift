import AudioToolbox
import CoreAudio
import Foundation

struct InputDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// CoreAudio のデバイス操作（マイク一覧・UID 解決・出力ミュート）
enum AudioDevices {
    static func inputDevices() -> [InputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard inputChannelCount(id) > 0, let uid = stringProperty(id, kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(id, kAudioObjectPropertyName)
            else { return nil }
            return InputDevice(id: id, uid: uid, name: name)
        }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        inputDevices().first { $0.uid == uid }?.id
    }

    static func defaultInputName() -> String? {
        guard let id = defaultDevice(kAudioHardwarePropertyDefaultInputDevice) else { return nil }
        return stringProperty(id, kAudioObjectPropertyName)
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else { return nil }
        return id
    }

    // MARK: - 音声入力中のミュート

    struct MuteToken {
        let device: AudioDeviceID
        let previousMute: UInt32?
        let previousVolume: Float32?
    }

    /// 既定の出力デバイスをミュートし、元に戻すためのトークンを返す。
    /// ミュートに対応しないデバイスでは音量を 0 にする。
    static func muteOutput() -> MuteToken? {
        guard let device = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else { return nil }
        var muteAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(device, &muteAddr),
           AudioObjectIsPropertySettable(device, &muteAddr, &settable) == noErr, settable.boolValue {
            var current: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &size, &current)
            if current == 1 { return nil }  // すでにミュート
            var one: UInt32 = 1
            AudioObjectSetPropertyData(device, &muteAddr, 0, nil, size, &one)
            return MuteToken(device: device, previousMute: current, previousVolume: nil)
        }

        var volAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &volAddr) else { return nil }
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &volAddr, 0, nil, &size, &volume) == noErr, volume > 0 else { return nil }
        var zero: Float32 = 0
        AudioObjectSetPropertyData(device, &volAddr, 0, nil, size, &zero)
        return MuteToken(device: device, previousMute: nil, previousVolume: volume)
    }

    static func restoreOutput(_ token: MuteToken) {
        if var mute = token.previousMute {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectSetPropertyData(token.device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
        }
        if var volume = token.previousVolume {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectSetPropertyData(token.device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)
        }
    }
}
