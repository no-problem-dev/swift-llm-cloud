#if canImport(SwiftUI)
import SwiftUI

/// Draws a vendor's logo at a square size.
///
/// Reads the artwork from the asset catalog bundled with this package, falling back to an SF
/// Symbol for a brand that has none. The logo is fitted, not filled, so it keeps its proportions
/// inside the square, and it carries the vendor name as its accessibility label.
public struct CloudProviderLogo: View {
    public let brand: CloudProviderBrand
    public var size: CGFloat

    public init(_ brand: CloudProviderBrand, size: CGFloat = 24) {
        self.brand = brand
        self.size = size
    }

    public var body: some View {
        Group {
            if brand.usesSystemImage {
                Image(systemName: brand.systemImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(brand.logoAssetName, bundle: .module)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(Text(brand.displayName))
    }
}
#endif
