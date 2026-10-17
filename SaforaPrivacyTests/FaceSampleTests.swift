//
//  FaceSampleTests.swift
//  SaforaPrivacyTests
//
//  Which faces count as "looking at the screen". Pure: no camera or Vision involved.
//

import Foundation
import Testing
@testable import SaforaPrivacy

@Suite("FaceSample")
struct FaceSampleTests {

    private func face(width: CGFloat = 0.3, yaw: Double? = 0, pitch: Double? = 0) -> DetectedFace {
        DetectedFace(width: width, height: width, yaw: yaw, pitch: pitch)
    }

    @Test func nobodyInViewCountsZero() {
        #expect(FaceSample(time: 0, faces: []).faceCount == 0)
    }

    @Test func ownerAloneCountsOne() {
        #expect(FaceSample(time: 0, faces: [face()]).faceCount == 1)
    }

    @Test func ownerCountsEvenWhenLookingAway() {
        // The largest face is the owner. Looking away must not make them disappear.
        #expect(FaceSample(time: 0, faces: [face(yaw: 1.2)]).faceCount == 1)
    }

    @Test func secondFaceLookingAtTheScreenCounts() {
        let sample = FaceSample(time: 0, faces: [face(width: 0.4), face(width: 0.15, yaw: 0.2, pitch: 0.3)])
        #expect(sample.faceCount == 2)
    }

    @Test func passerbyFacingSidewaysIsNotCounted() {
        let sample = FaceSample(time: 0, faces: [face(width: 0.4), face(width: 0.15, yaw: 1.1)])
        #expect(sample.faceCount == 1)
        #expect(sample.totalFaces == 2) // seen, but not looking at the screen
    }

    @Test func passerbyLookingUpOrDownFarIsNotCounted() {
        let sample = FaceSample(time: 0, faces: [face(width: 0.4), face(width: 0.15, pitch: 1.0)])
        #expect(sample.faceCount == 1)
    }

    @Test func tinyFacesAreIgnoredEntirely() {
        let sample = FaceSample(time: 0, faces: [face(width: 0.4), face(width: 0.02)])
        #expect(sample.faceCount == 1)
        #expect(sample.totalFaces == 1)
    }

    @Test func unknownHeadPoseCountsAsLooking() {
        // If Vision cannot tell, assume the safe side for privacy.
        let sample = FaceSample(time: 0, faces: [face(width: 0.4), face(width: 0.15, yaw: nil, pitch: nil)])
        #expect(sample.faceCount == 2)
    }

    @Test func largestFaceIsTheOwnerRegardlessOfOrder() {
        let sample = FaceSample(time: 0, faces: [face(width: 0.1, yaw: 1.2), face(width: 0.4, yaw: 1.2)])
        #expect(sample.faceCount == 1) // owner (0.4) counts, the sideways 0.1 face does not
    }

    @Test func severalViewersAreAllCounted() {
        let sample = FaceSample(time: 0, faces: [face(width: 0.4), face(width: 0.15), face(width: 0.12)])
        #expect(sample.faceCount == 3)
    }
}
