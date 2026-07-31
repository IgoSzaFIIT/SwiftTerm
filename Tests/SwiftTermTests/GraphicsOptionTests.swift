//
//  GraphicsOptionTests.swift
//
//  `TerminalOptions.enableGraphics` — the switch for the three inline image protocols.
//  Cases are written from the protocols' own grammars: the Kitty graphics protocol's control
//  keys (`a` action, `t` transmission medium, `f` format, `q` response suppression), the
//  Sixel DCS grammar (`DCS q … ST`) and iTerm2's `OSC 1337 ; File=…:<base64>`, plus DA1's
//  capability list, where parameter 4 is Sixel.
//
#if os(macOS)
import Foundation
import Testing
import Darwin

@testable import SwiftTerm

final class GraphicsOptionTests {
    @_silgen_name("shm_open")
    private static func swiftShmOpen(_ name: UnsafePointer<CChar>, _ oflag: Int32, _ mode: mode_t) -> Int32

    /// Collects everything the terminal would write back to the host, and every bitmap it would
    /// hand its view — the two observable ways a graphics sequence leaves a mark.
    final class Probe: TerminalDelegate {
        private(set) var sent: [UInt8] = []
        private(set) var images: [(width: Int, height: Int)] = []
        private(set) var encodedImages: [Int] = []
        private(set) var iTermPassThrough: [String] = []

        func send(source: Terminal, data: ArraySlice<UInt8>) {
            sent.append(contentsOf: data)
        }

        func createImageFromBitmap(source: Terminal, bytes: inout [UInt8], width: Int, height: Int) {
            images.append((width: width, height: height))
        }

        func createImage(source: Terminal, data: Data, width: ImageSizeRequest, height: ImageSizeRequest, preserveAspectRatio: Bool) {
            encodedImages.append(data.count)
        }

        func iTermContent(source: Terminal, content: ArraySlice<UInt8>) {
            iTermPassThrough.append(String(bytes: content, encoding: .utf8) ?? "")
        }

        var sentText: String { String(bytes: sent, encoding: .utf8) ?? "" }
    }

    private func makeTerminal(graphics: Bool) -> (terminal: Terminal, probe: Probe) {
        let probe = Probe()
        let terminal = Terminal(delegate: probe,
                                options: TerminalOptions(cols: 10, rows: 5, enableGraphics: graphics))
        return (terminal, probe)
    }

    /// An APC `G` sequence: `ESC _ G <control> ; <base64 payload> ESC \`.
    private func feedKitty(_ terminal: Terminal, control: String, payload: [UInt8]) {
        let base64 = Data(payload).base64EncodedString()
        terminal.feed(text: "\u{1b}_G\(control);\(base64)\u{1b}\\")
    }

    private func feedKitty(_ terminal: Terminal, control: String, path: String) {
        feedKitty(terminal, control: control, payload: Array(path.utf8))
    }

    /// A minimal, valid Sixel DCS: one magenta pixel band, `DCS q … ST`.
    private func feedSixel(_ terminal: Terminal) {
        terminal.feed(text: "\u{1b}Pq#0;2;100;0;100#0~~@@vv@@~~@@~~$#0?????????????~~@@~~$\u{1b}\\")
    }

    /// iTerm2's inline image: `OSC 1337 ; File=<arguments> : <base64 file contents> BEL`, with
    /// `inline=1` asking for it to be drawn in the grid rather than handed to the embedder.
    private func feedITerm2Inline(_ terminal: Terminal, arguments: String = "inline=1;width=4;height=2") {
        terminal.feed(text: "\u{1b}]1337;File=\(arguments):\(Self.onePixelPngBase64)\u{07}")
    }

    /// A 1×1 PNG — the smallest payload `createImage` will decode.
    private static let onePixelPngBase64 =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="

    private func screenText(_ terminal: Terminal) -> [String] {
        TerminalTestHarness.visibleLinesText(buffer: terminal.buffer, terminal: terminal)
    }

    /// DA1's answer as its parameter list: `CSI ? p1 ; p2 ; … c`. Parameter 4 is Sixel.
    private func deviceAttributeParameters(_ terminal: Terminal, _ probe: Probe) -> [String] {
        terminal.feed(text: "\u{1b}[c")
        let response = probe.sentText
        guard let open = response.firstIndex(of: "?"), let close = response.lastIndex(of: "c") else {
            return []
        }
        return response[response.index(after: open)..<close].split(separator: ";").map(String.init)
    }

    // MARK: - Off: nothing draws, nothing answers, nothing is opened

    @Test func supportQueryIsUnanswered() {
        let (terminal, probe) = makeTerminal(graphics: false)

        // The runtime probe Kitty-capable clients send: `a=q` with a 1×1 RGB payload, expecting
        // `;OK` back. Silence is what tells the client the terminal has no graphics protocol.
        feedKitty(terminal, control: "i=31,s=1,v=1,a=q,t=d,f=24", payload: [0, 0, 0])

        #expect(probe.sent.isEmpty)
    }

    @Test func directTransmitDrawsNothing() {
        let (terminal, probe) = makeTerminal(graphics: false)
        let before = screenText(terminal)

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=d,c=1,r=1,i=1,U=1", payload: [1, 2, 3])

        #expect(terminal.kittyGraphicsState.imagesById.isEmpty)
        #expect(terminal.kittyGraphicsState.placementsByKey.isEmpty)
        #expect(terminal.buffer.hasAnyImages == false)
        #expect(screenText(terminal) == before)
        #expect(probe.sent.isEmpty)
    }

    @Test func fileMediumIsNotRead() throws {
        let (terminal, probe) = makeTerminal(graphics: false)
        let file = try makeImageFile(named: "graphics-option-file")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let before = screenText(terminal)

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=f,c=1,r=1,i=1,U=1", path: file.path)

        #expect(terminal.kittyGraphicsState.imagesById.isEmpty)
        #expect(screenText(terminal) == before)
        // Not even a refusal: an error string discriminates between a path that exists and one
        // that does not, which is the oracle the silent refusal denies the host.
        #expect(probe.sent.isEmpty)
    }

    @Test func temporaryFileMediumIsNotReadAndNotDeleted() throws {
        let (terminal, probe) = makeTerminal(graphics: false)
        // `t=t` hands the terminal ownership of the file: it reads it and unlinks it. A file still
        // on disk afterwards is direct evidence the medium was never opened.
        let file = try makeImageFile(named: "tty-graphics-protocol-option")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=t,c=1,r=1,i=1,U=1", path: file.path)

        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(terminal.kittyGraphicsState.imagesById.isEmpty)
        #expect(probe.sent.isEmpty)
    }

    @Test func sharedMemoryMediumIsNotOpened() {
        let (terminal, probe) = makeTerminal(graphics: false)

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=s,c=1,r=1,i=1,U=1", path: Self.shmName())

        #expect(terminal.kittyGraphicsState.imagesById.isEmpty)
        #expect(probe.sent.isEmpty)
    }

    @Test(.enabled(if: GraphicsOptionTests.sharedMemoryAvailable()))
    func sharedMemoryObjectIsNotUnlinked() throws {
        let (terminal, probe) = makeTerminal(graphics: false)
        // `t=s` consumes the object: the terminal `shm_unlink`s whatever name it is handed,
        // whether or not it could read it. An object still openable afterwards is direct evidence
        // nothing reached that call.
        let name = Self.shmName()
        try #require(Self.createSharedMemory(name: name, bytes: [1, 2, 3]))
        defer { _ = name.withCString { shm_unlink($0) } }

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=s,c=1,r=1,i=1,U=1", path: name)

        #expect(Self.sharedMemoryExists(name: name))
        #expect(probe.sent.isEmpty)
    }

    /// A refused `G` is dropped, not handed to the unknown-APC fallback: that leg logs, and a host
    /// can send these as fast as it likes. Other APC commands still reach the fallback.
    @Test func aRefusedKittySequenceDoesNotReachTheUnknownApcFallback() {
        let (terminal, _) = makeTerminal(graphics: false)
        var seen: [UInt8] = []
        terminal.parser.apcHandlerFallback = { code, _ in seen.append(code) }

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=d,c=1,r=1,i=1,U=1", payload: [1, 2, 3])
        terminal.feed(text: "\u{1b}_Zwhatever\u{1b}\\")

        #expect(seen == [UInt8(ascii: "Z")])
    }

    @Test func sixelPayloadDrawsNothing() {
        let (terminal, probe) = makeTerminal(graphics: false)
        let before = screenText(terminal)

        feedSixel(terminal)

        #expect(probe.images.isEmpty)
        #expect(terminal.buffer.hasAnyImages == false)
        #expect(screenText(terminal) == before)
    }

    // MARK: - iTerm2 inline images

    /// The third inline image protocol: `OSC 1337 ; File=…;inline=1 : <base64>` carries the image
    /// in band and asks for it in the grid. With graphics off nothing is decoded.
    @Test func iTerm2InlineImageIsNotDecoded() {
        let (terminal, probe) = makeTerminal(graphics: false)
        let before = screenText(terminal)

        feedITerm2Inline(terminal)

        #expect(probe.encodedImages.isEmpty)
        #expect(terminal.buffer.hasAnyImages == false)
        #expect(screenText(terminal) == before)
    }

    /// A refused inline image is consumed and dropped, not re-routed to the embedder's
    /// `iTermContent` leg — that leg never sees an inline image when graphics are on either, so
    /// turning them off must not start feeding it image payloads.
    @Test func aRefusedInlineImageIsNotHandedToTheEmbedder() {
        let (terminal, probe) = makeTerminal(graphics: false)

        feedITerm2Inline(terminal)

        #expect(probe.iTermPassThrough.isEmpty)
    }

    /// `OSC 1337` is iTerm2's whole extension channel, not an image sequence — `SetMark`,
    /// `CurrentDir` and the rest ride it. The gate is the image branch alone, so everything else
    /// still reaches the embedder.
    @Test func anOrdinaryITerm2SequenceStillReachesTheEmbedder() {
        let (terminal, probe) = makeTerminal(graphics: false)

        terminal.feed(text: "\u{1b}]1337;CurrentDir=/somewhere\u{07}")

        #expect(probe.iTermPassThrough == ["CurrentDir=/somewhere"])
    }

    /// The non-inline form (`inline=0`) is a download the embedder is meant to handle, not
    /// something the terminal draws — it is unaffected by the graphics switch.
    @Test func theNonInlineFormIsUnaffected() {
        let (terminal, probe) = makeTerminal(graphics: false)

        feedITerm2Inline(terminal, arguments: "inline=0;name=Zm9v")

        #expect(probe.encodedImages.isEmpty)
        #expect(probe.iTermPassThrough.count == 1)
    }

    @Test func primaryDeviceAttributesOmitSixel() {
        let (terminal, probe) = makeTerminal(graphics: false)

        #expect(!deviceAttributeParameters(terminal, probe).contains("4"))
    }

    @Test func primaryDeviceAttributesOmitSixelEvenWhenSixelReportingIsAsked() {
        let probe = Probe()
        // The two options must not be able to disagree: graphics off wins over a caller that
        // still asks for the Sixel advertisement.
        let terminal = Terminal(delegate: probe,
                                options: TerminalOptions(cols: 10, rows: 5,
                                                         enableGraphics: false,
                                                         enableSixelReported: true))

        #expect(!deviceAttributeParameters(terminal, probe).contains("4"))
    }

    // MARK: - The vendored default is unchanged

    @Test func defaultOptionsAnswerTheSupportQuery() {
        let (terminal, probe) = makeTerminal(graphics: true)

        feedKitty(terminal, control: "i=31,s=1,v=1,a=q,t=d,f=24", payload: [0, 0, 0])

        #expect(probe.sentText.contains(";OK"))
    }

    @Test func defaultOptionsTransmitAndDisplay() {
        let (terminal, _) = makeTerminal(graphics: true)

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=d,c=1,r=1,i=1,U=1", payload: [1, 2, 3])

        #expect(terminal.kittyGraphicsState.imagesById[1] != nil)
        #expect(!terminal.kittyGraphicsState.placementsByKey.isEmpty)
    }

    @Test func defaultOptionsReadTheFileMedium() throws {
        let (terminal, _) = makeTerminal(graphics: true)
        let file = try makeImageFile(named: "graphics-option-file")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        feedKitty(terminal, control: "a=T,f=24,s=1,v=1,t=f,c=1,r=1,i=1,U=1", path: file.path)

        #expect(terminal.kittyGraphicsState.imagesById[1] != nil)
    }

    @Test func defaultOptionsDecodeSixel() {
        let (terminal, probe) = makeTerminal(graphics: true)

        feedSixel(terminal)

        #expect(!probe.images.isEmpty)
    }

    @Test func defaultOptionsDecodeTheITerm2InlineImage() {
        let (terminal, probe) = makeTerminal(graphics: true)

        feedITerm2Inline(terminal)

        #expect(!probe.encodedImages.isEmpty)
    }

    @Test func defaultOptionsAdvertiseSixel() {
        let (terminal, probe) = makeTerminal(graphics: true)

        #expect(deviceAttributeParameters(terminal, probe).contains("4"))
    }

    // MARK: - Helpers

    /// A 1×1 RGB image (`f=24`, `s=1`, `v=1`) in a directory of its own, so the temp-file medium's
    /// `tty-graphics-protocol` naming requirement can be met by the file name.
    private func makeImageFile(named name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftterm-graphics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data([1, 2, 3]).write(to: file)
        return file
    }

    /// macOS caps a POSIX shared-memory name at 31 bytes, so the name stays short deliberately —
    /// a longer one fails to create and would make the case vacuous.
    private static func shmName() -> String {
        "/stg-\(UUID().uuidString.prefix(8))"
    }

    private static func createSharedMemory(name: String, bytes: [UInt8]) -> Bool {
        let fd = name.withCString { swiftShmOpen($0, O_CREAT | O_EXCL | O_RDWR, 0o600) }
        guard fd >= 0 else { return false }
        defer { close(fd) }
        guard ftruncate(fd, off_t(bytes.count)) == 0 else {
            _ = name.withCString { shm_unlink($0) }
            return false
        }
        return true
    }

    private static func sharedMemoryExists(name: String) -> Bool {
        let fd = name.withCString { swiftShmOpen($0, O_RDONLY, 0) }
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    /// POSIX shared memory is unavailable in some sandboxes; the cases that need it are required
    /// rather than silently passing.
    static func sharedMemoryAvailable() -> Bool {
        let name = shmName()
        guard createSharedMemory(name: name, bytes: [0]) else { return false }
        _ = name.withCString { shm_unlink($0) }
        return true
    }
}

#endif
