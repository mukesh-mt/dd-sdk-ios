/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapNextButton() {
        buttons["NEXT"].safeTap(within: 5)
    }

    func wait(seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }
}

class SRMultipleViewsRecordingScenarioTests: IntegrationTests, RUMCommonAsserts, SRCommonAsserts {
    /// The minimal number of SR records expected in this test. If less records are produced, the test will fail.
    private let recordsCountBaseline = 30

    func testSRMultipleViewsRecordingScenario() throws {
        // RUM endpoint in `HTTPServerMock`
        let rumEndpoint = server.obtainUniqueRecordingSession()
        // SR endpoint in `HTTPServerMock`
        let srEndpoint = server.obtainUniqueRecordingSession()
        
        // Play scenario:
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "SRMultipleViewsRecordingScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumEndpoint.recordingURL,
                srEndpoint: srEndpoint.recordingURL
            )
        )
        for _ in (0..<5) {
            app.wait(seconds: 1)
            app.tapNextButton()
        }
        try app.endRUMSession() // show "end view"
        
        // Get RUM and SR raw requests from mock server:
        // - pull RUM data until the "end view" event is fetched
        // - pull SR dat aright after - we know it is delivered faster than RUM so we don't need to await any longer
        let rumSessionHasEndedCondition: ([Request]) throws -> Bool = { try RUMSessionMatcher.singleSession(from: $0)?.hasEnded() ?? false }
        let rawRUMRequests = try rumEndpoint.pullRecordedRequests(timeout: dataDeliveryTimeout, until: rumSessionHasEndedCondition)
        let rawSRRequests = try srEndpoint.getRecordedRequests()
        
        assertRUM(requests: rawRUMRequests)
        assertSR(requests: rawSRRequests)
        
        // Map raw requests into RUM Session and SR request matchers:
        let rumSession = try XCTUnwrap(RUMSessionMatcher.singleSession(from: rawRUMRequests))
        let srRequests = try SRRequestMatcher.from(requests: rawSRRequests)
        
        // Read SR segments from SR requests (one request = one segment):
        let segments = try srRequests.map { try SRSegmentMatcher.fromJSONData($0.segmentJSONData()) }
        
        XCTAssertFalse(rumSession.viewVisits.isEmpty, "There should be some RUM session")
        XCTAssertFalse(srRequests.isEmpty, "There should be some SR requests")
        XCTAssertFalse(segments.isEmpty, "There should be some SR segments")
        sendCIAppLog(rumSession)
        
        // Validate if RUM session links to SR replay through `has_replay` flag in RUM events.
        // - We can't (yet) reliably sync the begining of the replay with the begining of RUM session, hence some initial
        // RUM events will not have `has_replay: true`. For that reason, we only do broad assertion on "most" events.
        let rumEventsWithReplay = try rumSession.allEvents.filter { try $0.sessionHasReplay() == true }
        XCTAssertGreaterThan(Double(rumEventsWithReplay.count) / Double(rumSession.allEvents.count), 0.5, "Most RUM events must have `has_replay` flag set to `true`")
        
        // Validate SR (multipart) requests.
        for request in srRequests {
            // - Each request must reference RUM session:
            XCTAssertEqual(try request.applicationID(), rumSession.applicationID, "SR request must reference RUM application")
            XCTAssertEqual(try request.sessionID(), rumSession.sessionID, "SR request must reference RUM session")
            XCTAssertTrue(rumSession.containsView(with: try request.viewID()), "SR request must reference a known view ID from RUM session")
            
            // - Other, broad checks:
            XCTAssertGreaterThan(Int(try request.recordsCount()) ?? 0, 0, "SR request must include some records")
            XCTAssertGreaterThan(Int(try request.rawSegmentSize()) ?? 0, 0, "SR request must include non-empty segment information")
            XCTAssertEqual(try request.source(), "ios")
        }
        
        // Validate SR segments.
        for segment in segments {
            // - Each segment must reference RUM session:
            XCTAssertEqual(try segment.value("application.id"), rumSession.applicationID, "Segment must be linked to RUM application")
            XCTAssertEqual(try segment.value("session.id"), rumSession.sessionID, "Segment must be linked to RUM session")
            XCTAssertTrue(rumSession.containsView(with: try segment.value("view.id")), "Segment must be linked to RUM view")
            
            // - Other, broad checks:
            XCTAssertGreaterThan(try segment.value("records_count") as Int, 0, "Segment must include some records")
            XCTAssertEqual(try segment.value("records_count") as Int, try segment.array("records").count, "Records count must be consistent")
        }
        
        // Validate SR records.
        // - Only broad checks on record and wireframe volumes.
        let allRecords = try segments.flatMap { try $0.records() }
        XCTAssertGreaterThan(allRecords.count, recordsCountBaseline, "Expected at least \(recordsCountBaseline) records, got \(allRecords.count)")
        
        let fullSnapshotRecords = try segments.flatMap { try $0.fullSnapshotRecords() }
        XCTAssertGreaterThan(fullSnapshotRecords.count, 0, "Expected some 'full snapshot' records")
        for fullSnapshotRecord in fullSnapshotRecords {
            XCTAssertGreaterThan(try fullSnapshotRecord.wireframes().count, 0, "Each 'full snapshot' must include some wireframes")
//            print("🕵️‍♂️    → wireframes in FS = \(try fullSnapshotRecord.wireframes().count)")
        }

        let incrementalSnapshotRecords = try segments.flatMap { try $0.incrementalSnapshotRecords() }
        XCTAssertGreaterThan(incrementalSnapshotRecords.count, 0, "Expected some 'incremental snapshot' records")
        XCTAssertGreaterThan(try incrementalSnapshotRecords.filter({ try $0.has(incrementalDataType: .mutationData) }).count, 0, "Expected some wireframe mutations")
        XCTAssertGreaterThan(try incrementalSnapshotRecords.filter({ try $0.has(incrementalDataType: .pointerInteractionData) }).count, 0, "Expected some touch data")

        XCTAssertGreaterThan(try segments.flatMap({ try $0.records(type: .metaRecord) }).count, 0, "Expected some 'meta' records")
        XCTAssertGreaterThan(try segments.flatMap({ try $0.records(type: .focusRecord) }).count, 0, "Expected some 'focus' records")

//        print("🕵️‍♂️ allRecords.count = \(allRecords.count)")
//        print("🕵️‍♂️ fullSnapshotRecords.count = \(fullSnapshotRecords.count)")
//        print("🕵️‍♂️ incrementalSnapshotRecords.count = \(incrementalSnapshotRecords.count)")
//        print("🕵️‍♂️ metaRecord.count = \(try segments.flatMap({ try $0.records(type: .metaRecord) }).count)")
//        print("🕵️‍♂️ focusRecord.count = \(try segments.flatMap({ try $0.records(type: .focusRecord) }).count)")
//
//        print("🕵️‍♂️    → wireframe mutations.count = \(try incrementalSnapshotRecords.filter({ try $0.has(incrementalDataType: .mutationData) }).count)")
//        print("🕵️‍♂️    → touch data.count = \(try incrementalSnapshotRecords.filter({ try $0.has(incrementalDataType: .pointerInteractionData) }).count)")
    }
}
