import XCTest
@testable import GraphiteCore

final class LibraryListingTests: XCTestCase {
    private func entry(_ path: String, isDirectory: Bool = false, modified: TimeInterval = 0) throws -> VaultEntry {
        VaultEntry(path: try VaultPath(path), isDirectory: isDirectory, size: 0, modified: Date(timeIntervalSince1970: modified))
    }

    func testFoldersStayWhateverTheFilterAndTheListingKeepsItsOrder() throws {
        let entries = [try entry("BA1", isDirectory: true), try entry("Week 2.pdf"), try entry("Summary.md"), try entry("Board.png")]
        let notebooks = LibraryListing.items(ofSorted: entries, filter: .notebooks).map(\.path.rawValue)
        XCTAssertEqual(notebooks, ["BA1", "Week 2.pdf"])
        let all = LibraryListing.items(ofSorted: entries, filter: .all).map(\.path.rawValue)
        XCTAssertEqual(all, ["BA1", "Week 2.pdf", "Summary.md", "Board.png"], "A filter never sorts: the listing is already in the vault's order.")
    }

    func testFiltersMatchTheirKinds() {
        XCTAssertTrue(LibraryFilter.boards.includes(.canvas))
        XCTAssertTrue(LibraryFilter.boards.includes(.base))
        XCTAssertFalse(LibraryFilter.pictures.includes(.pdf))
        XCTAssertTrue(LibraryFilter.all.includes(.other))
    }
}
