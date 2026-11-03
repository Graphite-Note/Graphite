/**
 * File: LargeOperator.swift
 * -------------------------
 * Layer: Vendor (SwiftUIMath)
 * Description: The atom of a large operator and how its limits are set.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 02/11/2026
 */

import Foundation

extension Math {
  final class LargeOperator: Atom {
    var limits: Bool
    /// Graphite patch: `\limits` was written. Without it, `limits` stacks them in display style only.
    var stacksLimitsInEveryStyle = false

    init(_ largeOperator: LargeOperator) {
      self.limits = largeOperator.limits
      self.stacksLimitsInEveryStyle = largeOperator.stacksLimitsInEveryStyle
      super.init(largeOperator)
    }

    init(limits: Bool = false) {
      self.limits = limits
      super.init(type: .largeOperator)
    }
  }
}
