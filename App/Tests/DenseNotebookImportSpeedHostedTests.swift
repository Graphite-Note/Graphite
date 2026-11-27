/**
 * File: DenseNotebookImportSpeedHostedTests.swift
 * -----------------------------------------------
 * Layer: Tests
 * Description: A notebook page written as densely as a formula sheet is imported on the iPad in time linear in its
 *              strokes, with the time and the app's memory reported, as `DenseInkWritingTests` measures it on the Mac.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */
#if os(iOS)
import XCTest
import Darwin
import PDFKit
import PencilKit
import GraphiteCore
import NotebookImport
@testable import GraphiteApple

/// An import of a Goodnotes formula sheet (5,159 and 6,145 strokes on two pages) "took forever" on the iPad on
/// 2026-11-12 (BUG-IMPORT-03). The fix was measured on the Mac only; this measures it in the iPad app's process.
final class DenseNotebookImportSpeedHostedTests: XCTestCase {
    private struct NoFiles: ImportSourceFiles {
        struct MissingFile: Error {}

        func contents(of file: ImportedSourceFile) throws -> Data {
            throw MissingFile()
        }
    }

    /// A page plan of `strokeCount` handwritten strokes, each with its outline as Goodnotes gives one.
    private static func densePlan(strokeCount: Int, sourcePageNumber: Int = 1) -> ImportedPagePlan {
        let drawing = DenseHandwritingNotebook.drawing(strokeCount: strokeCount, seed: UInt64(sourcePageNumber))
        let strokes = drawing.strokes.map { stroke -> ImportedStroke in
            let samples = stroke.path.map { point in
                ImportedStrokeSample(location: point.location, width: Double(point.size.width), force: nil, azimuthRadians: nil, altitudeRadians: nil)
            }
            let outline = StrokeOutliner.subpaths(forSamples: samples.map { sample in VectorStrokeSample(point: sample.location, width: sample.width) })
            return ImportedStroke(ink: .pen, color: NotebookImportColor(red: 0, green: 0, blue: 0, alpha: 1), samples: samples, outline: outline)
        }
        return ImportedPagePlan(sourcePageNumber: sourcePageNumber, sizeInPoints: DenseHandwritingNotebook.pageSize,
                                background: .plainColor(NotebookImportColor(red: 1, green: 1, blue: 1, alpha: 1)), strokes: strokes, report: [])
    }

    private func importSeconds(of plans: [ImportedPagePlan], to destination: URL) throws -> Double {
        let start = ContinuousClock.now
        _ = try NotebookImportWriter(fileWriter: AtomicFileWriter()).write(sourcePageCount: plans.count, outcomeForPage: { pageIndex in .planned(plans[pageIndex]) },
                                                                           outline: [], sourceFiles: NoFiles(), strokeCreationDate: Date(timeIntervalSince1970: 0),
                                                                           to: destination, pageWillBeWritten: { _ in })
        let duration = ContinuousClock.now - start
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// The process's physical footprint, the figure the system's memory limit counts.
    private static func footprintMegabytes() -> Double {
        var information = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &information) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(information.phys_footprint) / 1_048_576
    }

    /// Four times the strokes take about four times as long, not sixteen: under 6 times is linear with room for noise.
    func testADensePageIsImportedInTimeLinearInItsStrokesOnTheIPad() throws {
        let vault = try TemporaryVault.make(prefix: "DenseNotebookImportSpeed", for: self)
        let footprintBefore = Self.footprintMegabytes()
        let lightSeconds = try importSeconds(of: [Self.densePlan(strokeCount: 1_000)], to: vault.location(of: "Light.pdf"))
        let denseSeconds = try importSeconds(of: [Self.densePlan(strokeCount: 4_000)], to: vault.location(of: "Dense.pdf"))
        let formulaSheetSeconds = try importSeconds(of: [Self.densePlan(strokeCount: 5_159), Self.densePlan(strokeCount: 6_145, sourcePageNumber: 2)],
                                                    to: vault.location(of: "Formula sheet.pdf"))
        let footprintAfter = Self.footprintMegabytes()
        let report = String(format: "1,000 strokes %.2f s, 4,000 strokes %.2f s, two pages of 5,159 and 6,145 strokes %.2f s; footprint %.0f MB before, %.0f MB after",
                            lightSeconds, denseSeconds, formulaSheetSeconds, footprintBefore, footprintAfter)
        print("DenseNotebookImportSpeedHostedTests: \(report)")
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertLessThan(denseSeconds, lightSeconds * 6, "Writing a page grows linearly with its strokes. \(report)")
        let page = try XCTUnwrap(PDFDocument(url: vault.location(of: "Dense.pdf"))?.page(at: 0))
        XCTAssertEqual(page.annotations.filter { annotation in annotation.type == "Ink" }.count, 4_000)
    }
}
#endif
