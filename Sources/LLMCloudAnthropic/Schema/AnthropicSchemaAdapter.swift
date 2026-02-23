import Foundation
import LLMClient

// MARK: - AnthropicSchemaAdapter

/// Anthropic API 用のスキーマ適合
public struct AnthropicSchemaAdapter: ProviderSchemaAdapter {
    public init() {}

    public func adapt(_ schema: JSONSchema) -> JSONSchema {
        adaptWithConstraints(schema, fieldPath: "").schema
    }

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

    public func adaptWithConstraints(_ schema: JSONSchema, fieldPath: String) -> SchemaAdaptationResult {
        var removedConstraints: [RemovedConstraint] = []

        let (adaptedProperties, propertyConstraints) = adaptPropertiesWithConstraints(
            schema.properties, parentPath: fieldPath
        )
        removedConstraints.append(contentsOf: propertyConstraints)

        let (adaptedItems, itemsConstraints) = adaptItemsWithConstraints(
            schema.items, parentPath: fieldPath
        )
        removedConstraints.append(contentsOf: itemsConstraints)

        var adaptedMinItems: Int? = nil
        if let minItems = schema.minItems {
            if minItems <= 1 {
                adaptedMinItems = minItems
            } else {
                removedConstraints.append(RemovedConstraint(
                    type: .minItems, fieldPath: fieldPath, value: .int(minItems)
                ))
            }
        }

        if let maxItems = schema.maxItems {
            removedConstraints.append(RemovedConstraint(
                type: .maxItems, fieldPath: fieldPath, value: .int(maxItems)
            ))
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

        let adaptedSchema = JSONSchema(
            type: schema.type,
            description: schema.description,
            properties: adaptedProperties,
            required: schema.required,
            items: adaptedItems,
            additionalProperties: schema.additionalProperties,
            minItems: adaptedMinItems,
            maxItems: nil,
            minimum: nil,
            maximum: nil,
            exclusiveMinimum: nil,
            exclusiveMaximum: nil,
            minLength: nil,
            maxLength: nil,
            pattern: schema.pattern,
            enum: schema.enum,
            format: schema.format
        )

        return SchemaAdaptationResult(
            schema: adaptedSchema,
            removedConstraints: removedConstraints
        )
    }
}
