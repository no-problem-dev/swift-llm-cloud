# ``LLMCloudBranding``

クラウド LLM プロバイダーのブランドロゴと表示 identity を提供する SwiftUI モジュール。

## Overview

`LLMCloudBranding` は、各クラウド LLM プロバイダー / モデルファミリーのブランド identity（表示名・ロゴアセット）を 1 モジュールに集約します。他のターゲットには一切依存せず、純粋な表示資産として機能します。

`CloudProviderBrand` でプロバイダーを特定し、`CloudProviderLogo` SwiftUI ビューでロゴを描画します。アセットは `ProviderLogos.xcassets`（モジュール同梱）に格納されており、アプリバンドルへのコピーは不要です。

### ロゴの表示

```swift
import LLMCloudBranding
import SwiftUI

struct ProviderRow: View {
    let brand: CloudProviderBrand

    var body: some View {
        HStack {
            CloudProviderLogo(brand, size: 32)
            Text(brand.displayName)
        }
    }
}

// 全プロバイダーを一覧表示
struct BrandList: View {
    var body: some View {
        List(CloudProviderBrand.allCases) { brand in
            ProviderRow(brand: brand)
        }
    }
}
```

### モデルファミリー名からブランドを解決

モデル ID やファミリー名だけからブランドを推定したい場合は `from(modelFamily:)` を使用します。

```swift
let brand = CloudProviderBrand.from(modelFamily: "claude")  // .anthropic
let brand = CloudProviderBrand.from(modelFamily: "gemini")  // .google
```

## Topics

### Brand Identity

- ``CloudProviderBrand``

### SwiftUI Views

- ``CloudProviderLogo``
