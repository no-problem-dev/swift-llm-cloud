import Foundation
import LLMClient

/// どの JSON Schema 制約をプロバイダがサポートするかを宣言する設定。
///
/// 各プロバイダの API 仕様（2026-05 時点）に基づく。プロバイダは差分（この設定値）
/// だけを供給し、再帰トラバースと制約除去ロジックは ``GenericSchemaAdapter`` に集約する。
package struct SchemaCapabilities: Sendable {
    package enum MinItemsPolicy: Sendable {
        /// 常に除去（OpenAI）。
        case remove
        /// 0/1 のみ許容、それ以外は除去（Anthropic は 0/1 のみ）。
        case keepIfAtMostOne
        /// そのまま保持（Gemini）。
        case keep
    }

    package enum FormatPolicy: Sendable {
        case keepAll
        case removeAll
        case whitelist(Set<String>)
    }

    package enum AdditionalPropertiesPolicy: Sendable {
        /// 元の値をそのまま（Anthropic）。
        case passthrough
        /// 常に除去（Gemini）。
        case removeToNil
        /// object には false を強制（OpenAI）。
        case forceFalseOnObjects
    }

    package enum RequiredPolicy: Sendable {
        case passthrough
        /// object の全プロパティを required にする（OpenAI strict）。
        case allPropertiesOnObjects
    }

    package var minItems: MinItemsPolicy
    package var maxItems: Bool
    package var numericRange: Bool
    package var exclusiveRange: Bool
    package var stringLength: Bool
    package var pattern: Bool
    package var format: FormatPolicy
    package var additionalProperties: AdditionalPropertiesPolicy
    package var required: RequiredPolicy

    package init(
        minItems: MinItemsPolicy,
        maxItems: Bool,
        numericRange: Bool,
        exclusiveRange: Bool,
        stringLength: Bool,
        pattern: Bool,
        format: FormatPolicy,
        additionalProperties: AdditionalPropertiesPolicy,
        required: RequiredPolicy
    ) {
        self.minItems = minItems
        self.maxItems = maxItems
        self.numericRange = numericRange
        self.exclusiveRange = exclusiveRange
        self.stringLength = stringLength
        self.pattern = pattern
        self.format = format
        self.additionalProperties = additionalProperties
        self.required = required
    }

    /// Anthropic Messages API（GA, constrained decoding）。
    package static let anthropic = SchemaCapabilities(
        minItems: .keepIfAtMostOne, maxItems: false, numericRange: false, exclusiveRange: false,
        stringLength: false, pattern: true, format: .keepAll,
        additionalProperties: .passthrough, required: .passthrough
    )

    /// OpenAI Structured Outputs（strict mode）。
    package static let openAI = SchemaCapabilities(
        minItems: .remove, maxItems: false, numericRange: false, exclusiveRange: false,
        stringLength: false, pattern: false, format: .removeAll,
        additionalProperties: .forceFalseOnObjects, required: .allPropertiesOnObjects
    )

    /// Google Gemini（responseSchema）。
    package static let gemini = SchemaCapabilities(
        minItems: .keep, maxItems: true, numericRange: true, exclusiveRange: false,
        stringLength: false, pattern: false, format: .whitelist(["date-time", "date", "time"]),
        additionalProperties: .removeToNil, required: .passthrough
    )
}

/// ``SchemaCapabilities`` 駆動の汎用スキーマアダプタ。
///
/// 適合後スキーマ（API へ送る内容）はプロバイダ固有実装とバイト一致し、除去された制約は
/// 同一集合として記録される（記録順のみ正規化）。各プロバイダの `*SchemaAdapter` は
/// `GenericSchemaAdapter(capabilities: .xxx)` への委譲に縮退する。
package struct GenericSchemaAdapter: ProviderSchemaAdapter {
    package let capabilities: SchemaCapabilities

    package init(capabilities: SchemaCapabilities) {
        self.capabilities = capabilities
    }

    package func adapt(_ schema: JSONSchema) -> JSONSchema {
        adaptWithConstraints(schema, fieldPath: "").schema
    }

    package func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        var removed: [RemovedConstraint] = []

        let (adaptedProperties, propertyConstraints) = adaptProperties(schema.properties, parentPath: fieldPath)
        removed.append(contentsOf: propertyConstraints)
        let (adaptedItems, itemsConstraints) = adaptItems(schema.items, parentPath: fieldPath)
        removed.append(contentsOf: itemsConstraints)

        // minItems
        var adaptedMinItems: Int?
        switch capabilities.minItems {
        case .keep:
            adaptedMinItems = schema.minItems
        case .keepIfAtMostOne:
            if let value = schema.minItems {
                if value <= 1 { adaptedMinItems = value }
                else { removed.append(.init(type: .minItems, fieldPath: fieldPath, value: .int(value))) }
            }
        case .remove:
            if let value = schema.minItems { removed.append(.init(type: .minItems, fieldPath: fieldPath, value: .int(value))) }
        }

        // maxItems / numericRange / exclusiveRange / stringLength / pattern
        let adaptedMaxItems = keepOrRemoveInt(schema.maxItems, kept: capabilities.maxItems, type: .maxItems, fieldPath: fieldPath, into: &removed)
        let adaptedMinimum = keepOrRemoveDouble(schema.minimum, kept: capabilities.numericRange, type: .minimum, fieldPath: fieldPath, into: &removed)
        let adaptedMaximum = keepOrRemoveDouble(schema.maximum, kept: capabilities.numericRange, type: .maximum, fieldPath: fieldPath, into: &removed)
        let adaptedExclMin = keepOrRemoveDouble(schema.exclusiveMinimum, kept: capabilities.exclusiveRange, type: .exclusiveMinimum, fieldPath: fieldPath, into: &removed)
        let adaptedExclMax = keepOrRemoveDouble(schema.exclusiveMaximum, kept: capabilities.exclusiveRange, type: .exclusiveMaximum, fieldPath: fieldPath, into: &removed)
        let adaptedMinLength = keepOrRemoveInt(schema.minLength, kept: capabilities.stringLength, type: .minLength, fieldPath: fieldPath, into: &removed)
        let adaptedMaxLength = keepOrRemoveInt(schema.maxLength, kept: capabilities.stringLength, type: .maxLength, fieldPath: fieldPath, into: &removed)
        var adaptedPattern: String?
        if let pattern = schema.pattern {
            if capabilities.pattern { adaptedPattern = pattern }
            else { removed.append(.init(type: .pattern, fieldPath: fieldPath, value: .string(pattern))) }
        }

        // format
        var adaptedFormat: String?
        if let format = schema.format {
            let keep: Bool
            switch capabilities.format {
            case .keepAll: keep = true
            case .removeAll: keep = false
            case .whitelist(let set): keep = set.contains(format)
            }
            if keep { adaptedFormat = format }
            else { removed.append(.init(type: .format, fieldPath: fieldPath, value: .string(format))) }
        }

        // additionalProperties
        let adaptedAdditional: Bool?
        switch capabilities.additionalProperties {
        case .passthrough: adaptedAdditional = schema.additionalProperties
        case .removeToNil: adaptedAdditional = nil
        case .forceFalseOnObjects: adaptedAdditional = schema.type == .object ? false : schema.additionalProperties
        }

        // required
        let adaptedRequired: [String]?
        switch capabilities.required {
        case .passthrough:
            adaptedRequired = schema.required
        case .allPropertiesOnObjects:
            adaptedRequired = adaptedProperties.map { Array($0.keys).sorted() } ?? schema.required
        }

        let adaptedSchema = JSONSchema(
            type: schema.type,
            description: schema.description,
            properties: adaptedProperties,
            required: adaptedRequired,
            items: adaptedItems,
            additionalProperties: adaptedAdditional,
            minItems: adaptedMinItems,
            maxItems: adaptedMaxItems,
            minimum: adaptedMinimum,
            maximum: adaptedMaximum,
            exclusiveMinimum: adaptedExclMin,
            exclusiveMaximum: adaptedExclMax,
            minLength: adaptedMinLength,
            maxLength: adaptedMaxLength,
            pattern: adaptedPattern,
            enum: schema.enum,
            format: adaptedFormat
        )
        return SchemaAdaptationResult(schema: adaptedSchema, removedConstraints: removed)
    }

    // MARK: - Helpers

    private func adaptProperties(_ properties: [String: JSONSchema]?, parentPath: String) -> ([String: JSONSchema]?, [RemovedConstraint]) {
        guard let properties else { return (nil, []) }
        var adapted: [String: JSONSchema] = [:]
        var constraints: [RemovedConstraint] = []
        for (key, value) in properties {
            let path = parentPath.isEmpty ? key : "\(parentPath).\(key)"
            let result = adaptWithConstraints(value, fieldPath: path)
            adapted[key] = result.schema
            constraints.append(contentsOf: result.removedConstraints)
        }
        return (adapted, constraints)
    }

    private func adaptItems(_ items: Box<JSONSchema>?, parentPath: String) -> (JSONSchema?, [RemovedConstraint]) {
        guard let items else { return (nil, []) }
        let result = adaptWithConstraints(items.value, fieldPath: "\(parentPath)[]")
        return (result.schema, result.removedConstraints)
    }

    private func keepOrRemoveInt(_ value: Int?, kept: Bool, type: ConstraintType, fieldPath: String, into removed: inout [RemovedConstraint]) -> Int? {
        guard let value else { return nil }
        if kept { return value }
        removed.append(.init(type: type, fieldPath: fieldPath, value: .int(value)))
        return nil
    }

    private func keepOrRemoveDouble(_ value: Double?, kept: Bool, type: ConstraintType, fieldPath: String, into removed: inout [RemovedConstraint]) -> Double? {
        guard let value else { return nil }
        if kept { return value }
        removed.append(.init(type: type, fieldPath: fieldPath, value: .double(value)))
        return nil
    }
}
