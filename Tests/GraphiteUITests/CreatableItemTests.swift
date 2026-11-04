/**
 * File: CreatableItemTests.swift
 * ------------------------------
 * Layer: Tests
 * Description: What the New menu offers on each device.
 *
 * Authors: Bahey Shalash
 * Version: 0.4
 * Date: 01/11/2026
 */

import XCTest
@testable import GraphiteUI

final class CreatableItemTests: XCTestCase {
    func testPencilFirstOffersTheNotebookFirst() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertEqual(offered.large, [.document(.notebook), .document(.note)])
    }

    func testKeyboardFirstOffersTheNoteFirst() {
        let offered = CreatableItem.offered(firstKind: .note, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertEqual(offered.large, [.document(.note), .document(.notebook)])
    }

    func testItemsOfTurnedOffPluginsAreLeftOut() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { plugin in plugin == .canvas }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertEqual(offered.others, [.document(.canvas), .pictureFromPhotos, .importFiles, .folder])
    }

    func testNotebookAndNoteAreAlwaysOffered() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertEqual(Set(offered.large), [.document(.notebook), .document(.note)])
        XCTAssertEqual(offered.others, [.pictureFromPhotos, .importFiles, .folder])
    }

    func testScanDocumentsIsOfferedOnlyWhereTheDeviceCanScan() {
        let unsupported = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertFalse(unsupported.others.contains(.scanDocuments))
        let supported = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: true, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertEqual(supported.others, [.document(.canvas), .document(.base), .dailyNote, .scanDocuments, .pictureFromPhotos, .importFiles, .folder])
    }

    func testScanDocumentsNeedsNoPluginSoItIsOfferedEvenWhenEveryPluginIsOff() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: true, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertEqual(offered.others, [.scanDocuments, .pictureFromPhotos, .importFiles, .folder])
    }

    func testTakePhotoIsOfferedOnlyWhereTheDeviceHasACamera() {
        let withoutCamera = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertFalse(withoutCamera.others.contains(.takePhoto))
        let withCamera = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: true, isEditable: { _ in true })
        XCTAssertEqual(withCamera.others, [.document(.canvas), .document(.base), .dailyNote, .pictureFromPhotos, .takePhoto, .importFiles, .folder])
    }

    func testImageFromPhotosNeedsNoPluginAndNoCamera() {
        let offered = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in false }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertTrue(offered.others.contains(.pictureFromPhotos))
    }

    /// HUNT-203: the Mac offered a Canvas and a Notebook it can only look at.
    func testAKindTheDeviceCannotEditIsNotOffered() {
        let notEditable: (CreationKind) -> Bool = { kind in kind != .notebook && kind != .canvas }
        let notebookFirst = CreatableItem.offered(firstKind: .notebook, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false, isEditable: notEditable)
        XCTAssertEqual(notebookFirst.large, [.document(.note)])
        XCTAssertEqual(notebookFirst.others, [.document(.base), .dailyNote, .pictureFromPhotos, .importFiles, .folder])
        let editsEverything = CreatableItem.offered(firstKind: .note, isEnabled: { _ in true }, canScanDocuments: false, canTakePhoto: false, isEditable: { _ in true })
        XCTAssertEqual(editsEverything.large, [.document(.note), .document(.notebook)])
    }

    func testOnlyTheMacLeavesOutWhatItCannotWriteIn() {
        #if os(macOS)
        XCTAssertFalse(CreationKind.notebook.canBeEditedOnThisDevice)
        XCTAssertFalse(CreationKind.canvas.canBeEditedOnThisDevice)
        #else
        XCTAssertTrue(CreationKind.notebook.canBeEditedOnThisDevice)
        XCTAssertTrue(CreationKind.canvas.canBeEditedOnThisDevice)
        #endif
        XCTAssertTrue(CreationKind.note.canBeEditedOnThisDevice)
        XCTAssertTrue(CreationKind.base.canBeEditedOnThisDevice)
    }
}
