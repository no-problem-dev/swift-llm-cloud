# ``LLMCloudBranding``

Provider logos and display names as a SwiftUI module, with no dependency on any client code.

## Overview

An app that lets users choose a provider needs the logo and the name, which is a presentation
concern that has nothing to do with sending requests. `LLMCloudBranding` isolates it: the module
depends on no other target in the package, so a settings screen or a model picker can render
without linking a single API client.

``CloudProviderBrand`` identifies a provider and carries its display name.
``CloudProviderLogo`` draws the mark. Artwork ships inside the module as a bundled asset catalog —
nothing to copy into the app bundle, and nothing to keep in sync.

### Drawing a logo

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
```

`CloudProviderBrand` is `CaseIterable`, so a full picker needs no hand-maintained list and gains
new providers when the package does.

```swift
struct BrandList: View {
    var body: some View {
        List(CloudProviderBrand.allCases) { brand in
            ProviderRow(brand: brand)
        }
    }
}
```

### Resolving a brand from a model name

When all you have is a model identifier — from a config file, a server response, or OpenRouter's
`provider/model` strings — `from(modelFamily:)` maps it to a brand.

```swift
CloudProviderBrand.from(modelFamily: "claude")  // .anthropic
CloudProviderBrand.from(modelFamily: "gemini")  // .google
```

An unrecognised family has no brand, so treat a `nil` result as "show a generic placeholder" rather
than as an error.

## Topics

### Brand identity

- ``CloudProviderBrand``

### SwiftUI views

- ``CloudProviderLogo``
