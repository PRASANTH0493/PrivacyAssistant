//
//  PrivacyRulesTests.swift
//  SaforaPrivacyTests
//
//  PrivacyRules is pure: tests use explicit timestamps. Defaults: onset 1.0s, recovery 3.0s.
//

import Foundation
import Testing
@testable import SaforaPrivacy

@Suite("PrivacyRules")
struct PrivacyRulesTests {

    @Test func oneFaceNeverWarns() {
        var rules = PrivacyRules()
        for time in stride(from: 0.0, through: 5.0, by: 0.5) {
            #expect(rules.update(faceCount: 1, at: time) == nil)
        }
    }

    @Test func multipleFacesWarnOnlyAfterOnset() {
        var rules = PrivacyRules()
        #expect(rules.update(faceCount: 2, at: 0) == nil)
        #expect(rules.update(faceCount: 2, at: 0.5) == nil)
        #expect(rules.update(faceCount: 2, at: 1.0) == .raise)
    }

    @Test func briefFalsePositiveNeverWarns() {
        var rules = PrivacyRules()
        _ = rules.update(faceCount: 1, at: 0)
        #expect(rules.update(faceCount: 2, at: 0.5) == nil)
        for time in stride(from: 1.0, through: 5.0, by: 0.5) {
            #expect(rules.update(faceCount: 1, at: time) == nil)
        }
    }

    @Test func detectorFlickerDoesNotRestartTheOnsetTimer() {
        var rules = PrivacyRules()
        #expect(rules.update(faceCount: 2, at: 0) == nil)
        #expect(rules.update(faceCount: 1, at: 0.3) == nil) // second face missed once
        #expect(rules.update(faceCount: 2, at: 0.6) == nil)
        #expect(rules.update(faceCount: 1, at: 0.9) == nil) // missed again
        #expect(rules.update(faceCount: 2, at: 1.2) == .raise)
    }

    @Test func aLongGapStartsTheOnsetOver() {
        var rules = PrivacyRules()
        _ = rules.update(faceCount: 2, at: 0)
        _ = rules.update(faceCount: 1, at: 0.5)
        _ = rules.update(faceCount: 1, at: 1.5) // longer than the 1.0s tolerance
        #expect(rules.update(faceCount: 2, at: 2.0) == nil)
        #expect(rules.update(faceCount: 2, at: 2.9) == nil)
        #expect(rules.update(faceCount: 2, at: 3.0) == .raise)
    }

    @Test func warningIsRaisedOnlyOncePerEpisode() {
        var rules = PrivacyRules()
        _ = rules.update(faceCount: 2, at: 0)
        #expect(rules.update(faceCount: 2, at: 1.0) == .raise)
        for time in stride(from: 1.5, through: 6.0, by: 0.5) {
            #expect(rules.update(faceCount: 3, at: time) == nil)
        }
    }

    @Test func warningClearsAfterRecoveryDuration() {
        var rules = PrivacyRules()
        _ = rules.update(faceCount: 2, at: 0)
        _ = rules.update(faceCount: 2, at: 1.0)
        #expect(rules.update(faceCount: 1, at: 1.5) == nil)
        #expect(rules.update(faceCount: 1, at: 4.4) == nil)
        #expect(rules.update(faceCount: 1, at: 4.5) == .clear)
    }

    @Test func multipleFacesDuringRecoveryRestartTheTimer() {
        var rules = PrivacyRules()
        _ = rules.update(faceCount: 2, at: 0)
        _ = rules.update(faceCount: 2, at: 1.0)
        _ = rules.update(faceCount: 1, at: 1.5)
        #expect(rules.update(faceCount: 2, at: 2.0) == nil)
        _ = rules.update(faceCount: 1, at: 2.5)
        #expect(rules.update(faceCount: 1, at: 5.4) == nil)
        #expect(rules.update(faceCount: 1, at: 5.5) == .clear)
    }

    @Test func nobodyInViewKeepsTheWarningAndRestartsRecovery() {
        var rules = PrivacyRules()
        _ = rules.update(faceCount: 2, at: 0)
        _ = rules.update(faceCount: 2, at: 1.0)
        _ = rules.update(faceCount: 1, at: 1.5)
        #expect(rules.update(faceCount: 0, at: 2.0) == nil)
        _ = rules.update(faceCount: 1, at: 2.5)
        #expect(rules.update(faceCount: 1, at: 5.4) == nil)
        #expect(rules.update(faceCount: 1, at: 5.5) == .clear)
    }

    @Test func newEpisodeWarnsAgainAfterRecovery() {
        var rules = PrivacyRules()
        _ = rules.update(faceCount: 2, at: 0)
        _ = rules.update(faceCount: 2, at: 1.0)
        _ = rules.update(faceCount: 1, at: 1.5)
        _ = rules.update(faceCount: 1, at: 4.5)
        _ = rules.update(faceCount: 2, at: 6.0)
        #expect(rules.update(faceCount: 2, at: 7.0) == .raise)
    }

    @Test func thresholdsAreConfigurable() {
        var rules = PrivacyRules(onset: 0.2, recovery: 1.0)
        _ = rules.update(faceCount: 2, at: 0)
        #expect(rules.update(faceCount: 2, at: 0.3) == .raise)
        _ = rules.update(faceCount: 1, at: 0.5)
        #expect(rules.update(faceCount: 1, at: 1.5) == .clear)
    }
}
