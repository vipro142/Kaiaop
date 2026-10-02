import XCTest
import Foundation

final class ProtocolTests: XCTestCase {
    func testSplitAndMultipleJSONMessages() throws {
        var parser = JSONLines()
        XCTAssertTrue(try parser.append(Data("{\"type\":\"po".utf8)).isEmpty)
        let messages = try parser.append(Data("ng\"}\n{\"type\":\"talkers\"}\n".utf8))
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["type"] as? String, "pong")
        XCTAssertEqual(messages[1]["type"] as? String, "talkers")
    }
    func testRejectMalformedAndOversizedFrames() {
        var parser = JSONLines()
        XCTAssertThrowsError(try parser.append(Data("invalid\n".utf8)))
        var large = JSONLines()
        XCTAssertThrowsError(try large.append(Data(repeating: 65, count: 262145)))
    }
    func testPCMFramingPreservesRemainderAndOrder() {
        var frames = PCMFrames()
        XCTAssertTrue(frames.append(Data(repeating: 1, count: 300)).isEmpty)
        let result = frames.append(Data(repeating: 2, count: 980))
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0], Data(repeating: 1, count: 300) + Data(repeating: 2, count: 340))
        XCTAssertEqual(result[1], Data(repeating: 2, count: 640))
        _ = frames.append(Data(repeating: 3, count: 10)); frames.clear()
        XCTAssertTrue(frames.append(Data(repeating: 4, count: 630)).isEmpty)
    }
    func testProfileValidationAndRegistration() {
        var p = JoinProfile(); XCTAssertFalse(p.valid)
        p.name = "  Kai  "; p.number = 30; p.cameraNumber = 30
        XCTAssertTrue(p.valid)
        let json = p.registration(clientID: "test-client")
        XCTAssertEqual(json["name"] as? String, "Kai")
        XCTAssertEqual(json["deviceId"] as? String, "EVENT_A_CAMERA_30")
        XCTAssertEqual(json["protocolVersion"] as? Int, 4)
        p.cameraNumber = 31; XCTAssertFalse(p.valid)
        p.role = .makeup; XCTAssertTrue(p.valid)
        XCTAssertEqual(p.registration(clientID: "x")["cameraNumber"] as? Int, 0)
        p.number = 300; XCTAssertTrue(p.valid)
        p.number = 301; XCTAssertFalse(p.valid)
        p.number = 1; p.name = "Kai\n"; XCTAssertTrue(p.valid)
        p.name = "Kai\nMedia"; XCTAssertFalse(p.valid)
        p.name = String(repeating: "a", count: 41); XCTAssertFalse(p.valid)
    }
    func testBackgroundMicrophonePolicy() {
        XCTAssertTrue(BackgroundMicPolicy.shouldRelease(active: false, latched: false))
        XCTAssertFalse(BackgroundMicPolicy.shouldRelease(active: false, latched: true))
        XCTAssertFalse(BackgroundMicPolicy.shouldRelease(active: true, latched: false))
        XCTAssertFalse(BackgroundMicPolicy.shouldRelease(active: true, latched: true))
    }
    func testMemberParsing() {
        XCTAssertNil(Member(["deviceId":"bad", "role":"UNKNOWN"]))
        let member = Member(["deviceId":"EVENT_A_CAMERA_2", "role":"CAMERA", "number":2, "cameraNumber":7, "name":"Kai"])
        XCTAssertEqual(member?.roleTitle, "Camera 07")
        XCTAssertEqual(member?.number, 2)
        XCTAssertEqual(CrewRole.allCases.count, 7)
        XCTAssertEqual(JoinProfile.rooms.count, 10)
    }
}
