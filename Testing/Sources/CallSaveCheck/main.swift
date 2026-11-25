import AVFoundation
import Foundation
import WorkbenchCore

@testable import LocalSources

/// Shows that a call track survives a change of microphone format and a failing write. Every buffer is synthetic and
/// built in memory; no device, microphone or capture session is used. Before the fix, the same inputs gave "could
/// not save the me track ... error -50" (channel count change) or a track of the wrong length (rate change).

var failures = 0

func check(_ name: String, _ ok: Bool) {
    print("  \(ok ? "ok  " : "FAIL") \(name)")
    if !ok { failures += 1 }
}

func heading(_ text: String) { print("\n\(text)") }

func format(rate: Double = 48000, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
    guard channels > 2 else { return AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)! }
    let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)!
    return AVAudioFormat(standardFormatWithSampleRate: rate, channelLayout: layout)
}

func tone(seconds: Double, rate: Double = 48000, channels: AVAudioChannelCount = 1) -> AVAudioPCMBuffer {
    let format = format(rate: rate, channels: channels)
    let frames = AVAudioFrameCount(seconds * rate)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    for channel in 0..<Int(channels) {
        for index in 0..<Int(frames) { buffer.floatChannelData![channel][index] = sin(Float(index) * 0.3) * 0.5 }
    }
    return buffer
}

let scratch = FileManager.default.temporaryDirectory.appending(path: "call-save-\(UUID().uuidString)")
defer { try? FileManager.default.removeItem(at: scratch) }

func newFolder() throws -> URL {
    let url = scratch.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func seconds(_ outcome: TrackOutcome) -> Double { outcome.files.map(CallTracks.duration(of:)).reduce(0, +) }

func near(_ value: Double, _ expected: Double) -> Bool { abs(value - expected) < 0.03 }

func outcome(of buffers: [AVAudioPCMBuffer], start: AVAudioFormat = format(), segment: TimeInterval = 300) throws
    -> TrackOutcome
{
    let sink = AudioFileSink(folder: try newFolder(), track: "me", format: start, segment: segment)
    buffers.forEach(sink.write)
    return sink.finish()
}

try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

heading("1. A change of input format in the middle of a call is saved whole")
let sameFormat = try outcome(of: [tone(seconds: 0.5), tone(seconds: 0.5)])
check("same format: 1.0 s saved, nothing lost (control)", near(seconds(sameFormat), 1.0) && sameFormat.lost == 0)
let channelChange = try outcome(of: [tone(seconds: 0.5), tone(seconds: 0.5, channels: 2)])
check(
    "mono then stereo (was error -50): 1.0 s saved, nothing lost",
    near(seconds(channelChange), 1.0) && channelChange.lost == 0)
let rateChange = try outcome(of: [tone(seconds: 0.5), tone(seconds: 0.5, rate: 16000)])
check(
    "48 kHz then 16 kHz (was 0.67 s): 1.0 s saved, nothing lost",
    near(seconds(rateChange), 1.0) && rateChange.lost == 0)
let rateAndChannels = try outcome(of: [tone(seconds: 0.5), tone(seconds: 0.5, rate: 24000, channels: 2)])
check("rate and channels together: 1.0 s saved", near(seconds(rateAndChannels), 1.0) && rateAndChannels.lost == 0)
let manyChannels = try outcome(
    of: [tone(seconds: 0.5, channels: 5), tone(seconds: 0.5, channels: 5)], start: format(channels: 5))
check("five-channel input from the first buffer (was error -50): 1.0 s saved", near(seconds(manyChannels), 1.0))
let afterRollover = try outcome(
    of: [tone(seconds: 0.6), tone(seconds: 0.6), tone(seconds: 0.6, rate: 16000, channels: 2)], segment: 1)
check(
    "change after a new part opened: 1.8 s saved in two or more parts",
    afterRollover.files.count >= 2 && near(seconds(afterRollover), 1.8))

heading("2. A buffer with no frames, and a write after the end")
let withEmpty = try outcome(of: [tone(seconds: 0.5), tone(seconds: 0), tone(seconds: 0.5)])
check("a zero-length buffer is skipped and costs nothing", near(seconds(withEmpty), 1.0) && withEmpty.lost == 0)
let closedSink = AudioFileSink(folder: try newFolder(), track: "me", format: format())
closedSink.write(tone(seconds: 0.5))
let closed = closedSink.finish()
closedSink.write(tone(seconds: 0.5))
check("a write after finish adds nothing", closedSink.finish() == closed)

heading("3. A failing write keeps the earlier audio and is counted")
let folder = try newFolder()
let sink = AudioFileSink(folder: folder, track: "me", format: format(), segment: 1)
sink.write(tone(seconds: 1.2))
try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
sink.write(tone(seconds: 0.4))
sink.write(tone(seconds: 0.2))
try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
sink.write(tone(seconds: 0.5))
let afterFailure = sink.finish()
check("two writes failed: 0.6 s counted as lost", near(afterFailure.lost, 0.6))
check("the sound before the failure is still readable", CallTracks.duration(of: afterFailure.files[0]) > 1.1)
check(
    "the track went on when the folder worked again", afterFailure.files.count == 2 && near(seconds(afterFailure), 1.7))
let fresh = AudioFileSink(folder: try newFolder(), track: "me", format: format())
fresh.write(tone(seconds: 0.5))
fresh.noteLost(2.5)
check("sound that never arrived is added to the loss", near(fresh.finish().lost, 2.5))

heading("4. What the person reads")
func whole(_ track: String) -> TrackOutcome {
    TrackOutcome(track: track, files: [URL(filePath: "/x/\(track)-001.m4a")], lost: 0)
}
func partly(_ track: String, lost: TimeInterval) -> TrackOutcome {
    TrackOutcome(track: track, files: [URL(filePath: "/x/\(track)-001.m4a")], lost: lost)
}
func notSaved(_ track: String, lost: TimeInterval = 0) -> TrackOutcome {
    TrackOutcome(track: track, files: [], lost: lost)
}
func note(_ tracks: TrackOutcome...) -> String? { CallAudioResult(tracks: tracks).lossNote }

check("every track whole: no note", note(whole("me"), whole("them")) == nil)
let someLost = note(partly("me", lost: 252.2), whole("them"))
print("  note: \(someLost ?? "nil")")
check(
    "part of my voice lost: says what is missing and that the other side is whole",
    someLost == "Your voice was saved, but 4 min 13 s of it is missing. The other side was saved in full.")
let allLost = note(notSaved("me", lost: 30), whole("them"))
print("  note: \(allLost ?? "nil")")
check(
    "my whole track lost: says so and keeps the other side",
    allLost == "Your voice was not saved. The other side was saved in full.")
let otherLost = note(whole("me"), partly("them", lost: 5))
check(
    "the other side lost 5 s: names the other side",
    otherLost == "The other side was saved, but 5 s of it is missing. Your voice was saved in full.")
let silent = note(notSaved("me"))
check("a track that got no sound says so", silent == "Your voice got no sound, so nothing of it was saved.")
check(
    "no note carries a system code",
    [someLost, allLost, otherLost, silent].allSatisfy { !($0 ?? "").contains("-50") && !($0 ?? "").contains("error") })
check("files of the result are all files kept", CallAudioResult(tracks: [whole("me"), whole("them")]).files.count == 2)
check("a result with no file has none", CallAudioResult(tracks: [notSaved("me", lost: 3)]).files.isEmpty)

heading("5. One meeting in two calendars is listed once")
let noon = Date(timeIntervalSince1970: 1_800_000_000)
func meeting(_ id: String, _ title: String, at start: Date) -> Meeting {
    Meeting(id: id, calendar: "c-\(id)", title: title, start: start, end: start.addingTimeInterval(1800))
}
let listed = Meeting.distinct([
    meeting("a", "Quarterly review", at: noon), meeting("b", "Quarterly review", at: noon),
    meeting("c", "Quarterly review", at: noon.addingTimeInterval(3600)), meeting("d", "Standup", at: noon),
])
check("the same title and time in two calendars gives one meeting", listed.map(\.id) == ["a", "c", "d"])
check("the same title at another time stays", listed.filter { $0.title == "Quarterly review" }.count == 2)

print(failures == 0 ? "\nALL OK" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
