/**
 * File: AddOnLibraryFailureTests.swift
 * ------------------------------------
 * Layer: Tests
 * Description: Checks which reason an add-on download failure is given.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import XCTest
import GraphiteApple
@testable import GraphiteUI

/// HUNT-233: errors other than four network ones fell to "could not be saved on this device", which blames local storage.
@MainActor
final class AddOnLibraryFailureTests: XCTestCase {
    func testEveryNetworkErrorIsAFailedConnection() {
        let networkCodes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
                                             .dnsLookupFailed, .dataNotAllowed, .secureConnectionFailed, .internationalRoamingOff, .callIsActive]
        for code in networkCodes {
            XCTAssertEqual(AddOnLibrary.failure(for: URLError(code)), .noConnection, "\(code.rawValue)")
        }
    }

    func testFileErrorsStayCouldNotSave() {
        XCTAssertEqual(AddOnLibrary.failure(for: CocoaError(.fileWriteOutOfSpace)), .couldNotSave)
        XCTAssertEqual(AddOnLibrary.failure(for: CocoaError(.fileWriteNoPermission)), .couldNotSave)
    }

    func testTheStoresOwnErrorsKeepTheirReasons() {
        XCTAssertEqual(AddOnLibrary.failure(for: AddOnPackStore.InstallError.fileDoesNotMatch(fileName: "a.png")), .damagedFile)
        XCTAssertEqual(AddOnLibrary.failure(for: AddOnPackStore.InstallError.unexpectedResponse(fileName: "a.png", statusCode: 404)), .serverRefused)
    }
}
