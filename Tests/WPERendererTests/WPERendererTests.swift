import XCTest
@testable import WPELibrary
@testable import WPERenderer

final class WPERendererTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wpe-libtest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func writeProject(_ json: String, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: dir.appendingPathComponent("project.json"))
    }

    func testLibraryScanFindsValidVideoAndSkipsBroken() throws {
        // valid video item with its entry file present
        let valid = tempRoot.appendingPathComponent("123456")
        try writeProject(
            #"{"type":"video","title":"Test Video","file":"wall.mp4"}"#, to: valid)
        try Data().write(to: valid.appendingPathComponent("wall.mp4"))

        // broken manifest → skipped, keeps library usable
        let broken = tempRoot.appendingPathComponent("222222")
        try writeProject("{not json", to: broken)

        // no manifest at all → skipped
        let empty = tempRoot.appendingPathComponent("333333")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let items = try LibraryStore().scan(folder: tempRoot)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, "123456")
        XCTAssertEqual(items[0].project.type, "video")
        XCTAssertEqual(items[0].project.title, "Test Video")
        XCTAssertTrue(items[0].isSupported)
        XCTAssertEqual(items[0].entryFileURL()?.lastPathComponent, "wall.mp4")
    }

    func testEntryFileURLIsNilWhenFileMissing() throws {
        let dir = tempRoot.appendingPathComponent("999999")
        try writeProject(#"{"type":"video","title":"No File","file":"missing.mp4"}"#, to: dir)
        let items = try LibraryStore().scan(folder: tempRoot)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items[0].entryFileURL())
    }

    func testApplicationTypeIsUnsupported() throws {
        let dir = tempRoot.appendingPathComponent("444444")
        try writeProject(#"{"type":"application","title":"Win Only","file":"x.exe"}"#, to: dir)
        let items = try LibraryStore().scan(folder: tempRoot)
        XCTAssertEqual(items.count, 1)
        XCTAssertFalse(items[0].isSupported)
        let err = UnsupportedWallpaperError("application")
        XCTAssertTrue(err.description.contains("application"))
    }
}
