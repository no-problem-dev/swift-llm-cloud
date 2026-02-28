import LLMClient
import Foundation

/// OpenAI API 用のスキーマ適合
///
/// OpenAI Structured Outputs には厳格な制約があります。
/// このアダプターはこれらの制約に適合したスキーマを生成します。
///
/// ## OpenAI Structured Outputs の制約
///
/// - `additionalProperties`: オブジェクト型では必ず `false` に設定
/// - `required`: すべてのプロパティを含める必要がある
/// - オプショナルフィールドは型を `["original_type", "null"]` の union 型で表現
///
/// ## サポートされていない制約（プロンプトに変換）
///
/// - `format`: 未サポート
/// - `minLength`, `maxLength`: 未サポート
/// - `pattern`: 未サポート
/// - `minimum`, `maximum`: 未サポート
/// - `exclusiveMinimum`, `exclusiveMaximum`: 未サポート
/// - `minItems`, `maxItems`: 未サポート
///
/// ## サポートされている制約
///
/// - `enum`: 列挙値
public struct OpenAISchemaAdapter: ProviderSchemaAdapter {
    public init() {}

    // MARK: - Private Helpers

    private func adaptPropertiesWithConstraints(
        _ properties: [String: JSONSchema]?,
        parentPath: String
    ) -> ([String: JSONSchema]?, [RemovedConstraint]) {
        guard let properties = properties else { return (nil, []) }
        var adaptedProperties: [String: JSONSchema] = [:]
        var allConstraints: [RemovedConstraint] = []
        for (key, value) in properties {
            let fieldPath = parentPath.isEmpty ? key : "\(parentPath).\(key)"
            let result = adaptWithConstraints(value, fieldPath: fieldPath)
            adaptedProperties[key] = result.schema
            allConstraints.append(contentsOf: result.removedConstraints)
        }
        return (adaptedProperties, allConstraints)
    }

    private func adaptItemsWithConstraints(
        _ items: Box<JSONSchema>?,
        parentPath: String
    ) -> (JSONSchema?, [RemovedConstraint]) {
        guard let items = items else { return (nil, []) }
        let itemPath = "\(parentPath)[]"
        let result = adaptWithConstraints(items.value, fieldPath: itemPath)
        return (result.schema, result.removedConstraints)
    }

    // MARK: - ProviderSchemaAdapter

    public func adapt(_ schema: JSONSchema) -> JSONSchema {
        adaptWithConstraints(schema, fieldPath: "").schema
    }

    public func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        var removedConstraints: [RemovedConstraint] = []

        let (adaptedProperties, propertyConstraints) = adaptPropertiesWithConstraints(
            schema.properties,
            parentPath: fieldPath
        )
        removedConstraints.append(contentsOf: propertyConstraints)

        let (adaptedItems, itemsConstraints) = adaptItemsWithConstraints(
            schema.items,
            parentPath: fieldPath
        )
        removedConstraints.append(contentsOf: itemsConstraints)

        let allRequired: [String]?
        if let props = adaptedProperties {
            allRequired = Array(props.keys).sorted()
        } else {
            allRequired = schema.required
        }

        if let minimum = schema.minimum {
            removedConstraints.append(RemovedConstraint(
                type: .minimum, fieldPath: fieldPath, value: .int(minimum)
            ))
        }

        if let maximum = schema.maximum {
            removedConstraints.append(RemovedConstraint(
                type: .maximum, fieldPath: fieldPath, value: .int(maximum)
            ))
        }

        if let exclusiveMinimum = schema.exclusiveMinimum {
            removedConstraints.append(RemovedConstraint(
                type: .exclusiveMinimum, fieldPath: fieldPath, value: .int(exclusiveMinimum)
            ))
        }

        if let exclusiveMaximum = schema.exclusiveMaximum {
            removedConstraints.append(RemovedConstraint(
                type: .exclusiveMaximum, fieldPath: fieldPath, value: .int(exclusiveMaximum)
            ))
        }

        if let minLength = schema.minLength {
            removedConstraints.append(RemovedConstraint(
                type: .minLength, fieldPath: fieldPath, value: .int(minLength)
            ))
        }

        if let maxLength = schema.maxLength {
            removedConstraints.append(RemovedConstraint(
                type: .maxLength, fieldPath: fieldPath, value: .int(maxLength)
            ))
        }

        if let pattern = schema.pattern {
            removedConstraints.append(RemovedConstraint(
                type: .pattern, fieldPath: fieldPath, value: .string(pattern)
            ))
        }

        if let minItems = schema.minItems {
            removedConstraints.append(RemovedConstraint(
                type: .minItems, fieldPath: fieldPath, value: .int(minItems)
            ))
        }

        if let maxItems = schema.maxItems {
            removedConstraints.append(RemovedConstraint(
                type: .maxItems, fieldPath: fieldPath, value: .int(maxItems)
            ))
        }

        if let format = schema.format {
            removedConstraints.append(RemovedConstraint(
                type: .format, fieldPath: fieldPath, value: .string(format)
            ))
        }

        let adaptedSchema = JSONSchema(
            type: schema.type,
            description: schema.description,
            properties: adaptedProperties,
            required: allRequired,
            items: adaptedItems,
            additionalProperties: schema.type == .object ? false : schema.additionalProperties,
            minItems: nil,
            maxItems: nil,
            minimum: nil,
            maximum: nil,
            exclusiveMinimum: nil,
            exclusiveMaximum: nil,
            minLength: nil,
            maxLength: nil,
            pattern: nil,
            enum: schema.enum,
            format: nil
        )

        return SchemaAdaptationResult(
            schema: adaptedSchema,
            removedConstraints: removedConstraints
        )
    }
}
