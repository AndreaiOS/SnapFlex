// Core/Sources/SnapFlexCore/ETTR.swift

public enum ETTR {
    /// Suggested exposure delta in EV stops for a 192-bin luma histogram.
    /// Positive brightens. 0 when converged (or histogram empty/degenerate).
    public static func adjustment(bins: [UInt32],
                                  clipFraction: Double = 0.005,
                                  targetTopBins: Int = 12) -> Double {
        // Guard: bins.count must be >= 4
        guard bins.count >= 4 else { return 0 }

        // Calculate total
        let total = bins.reduce(0, +)

        // Empty/all-zero histogram
        guard total > 0 else { return 0 }

        // Check for clipping: top 2 bins / total > clipFraction
        let topTwoBins = UInt32(bins[safe: bins.count - 2] ?? 0) + UInt32(bins[safe: bins.count - 1] ?? 0)
        let clippedMass = Double(topTwoBins) / Double(total)

        if clippedMass > clipFraction {
            return -0.3
        }

        // Find brightest nonzero bin index
        if let brightestIndex = bins.lastIndex(where: { $0 > 0 }) {
            // If brightest nonzero bin index < bins.count - targetTopBins, step up
            if brightestIndex < bins.count - targetTopBins {
                return 0.3
            }
        }

        // Converged
        return 0
    }
}

// Safe array subscript extension
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
