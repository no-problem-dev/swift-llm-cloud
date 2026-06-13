#if canImport(SwiftUI)
import SwiftUI

/// プロバイダー / モデルファミリーのブランドロゴを表示するビュー。
///
/// `ProviderLogos.xcassets`（このパッケージに同梱）から brand のロゴを描画する。
/// アセットが無い brand は SF Symbols へフォールバックする。
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
