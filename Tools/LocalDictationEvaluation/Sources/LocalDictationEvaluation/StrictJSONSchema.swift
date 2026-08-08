import Foundation

public struct StrictJSONIssue: Equatable, Sendable {
  public let path: String
  public let key: String

  public init(path: String, key: String) {
    self.path = path
    self.key = key
  }
}

public enum StrictJSONSchemaError: Error, Equatable, Sendable {
  case invalidSchema
  case invalidInstance
}

public enum StrictJSONSchema {
  private static let supportedTypes: Set<String> = [
    "array", "boolean", "integer", "null", "number", "object", "string"
  ]

  public static func unknownKeyIssues(
    instanceData: Data,
    schemaData: Data
  ) throws -> [StrictJSONIssue] {
    let instance: Any
    do {
      instance = try JSONSerialization.jsonObject(with: instanceData)
    } catch {
      throw StrictJSONSchemaError.invalidInstance
    }
    let schemaObject: Any
    do {
      schemaObject = try JSONSerialization.jsonObject(with: schemaData)
    } catch {
      throw StrictJSONSchemaError.invalidSchema
    }
    guard let root = schemaObject as? [String: Any] else {
      throw StrictJSONSchemaError.invalidSchema
    }
    try validateSchema(root, root: root, isRoot: true, resolving: [])
    return try walk(instance: instance, schema: root, root: root, path: "")
      .sorted { ($0.path, $0.key) < ($1.path, $1.key) }
  }

  private static func walk(
    instance: Any,
    schema: [String: Any],
    root: [String: Any],
    path: String,
    resolving: Set<String> = []
  ) throws -> [StrictJSONIssue] {
    if let reference = schema["$ref"] as? String {
      let resolved = try resolve(reference, root: root, resolving: resolving)
      return try walk(
        instance: instance,
        schema: resolved.schema,
        root: root,
        path: path,
        resolving: resolved.resolving
      )
    }
    if let branches = schema["anyOf"] as? [Any] {
      for branch in branches {
        guard let branch = branch as? [String: Any] else {
          throw StrictJSONSchemaError.invalidSchema
        }
        if matches(instance: instance, schema: branch, root: root, resolving: resolving) {
          return try walk(
            instance: instance,
            schema: branch,
            root: root,
            path: path,
            resolving: resolving
          )
        }
      }
      return []
    }

    let types = try types(in: schema)
    if types.contains("object"), let object = instance as? [String: Any] {
      guard let properties = schema["properties"] as? [String: Any] else {
        throw StrictJSONSchemaError.invalidSchema
      }
      var issues: [StrictJSONIssue] = []
      for key in object.keys.sorted() {
        guard let property = properties[key] as? [String: Any] else {
          if schema["additionalProperties"] as? Bool == false {
            issues.append(StrictJSONIssue(
              path: "\(path)/\(escape(key))",
              key: key
            ))
          }
          continue
        }
        issues.append(contentsOf: try walk(
          instance: object[key] as Any,
          schema: property,
          root: root,
          path: "\(path)/\(escape(key))",
          resolving: resolving
        ))
      }
      return issues
    }
    if types.contains("array"), let array = instance as? [Any] {
      guard let itemSchema = schema["items"] as? [String: Any] else {
        throw StrictJSONSchemaError.invalidSchema
      }
      var issues: [StrictJSONIssue] = []
      for (index, item) in array.enumerated() {
        issues.append(contentsOf: try walk(
          instance: item,
          schema: itemSchema,
          root: root,
          path: "\(path)/\(index)",
          resolving: resolving
        ))
      }
      return issues
    }
    return []
  }

  private static func matches(
    instance: Any,
    schema: [String: Any],
    root: [String: Any],
    resolving: Set<String>
  ) -> Bool {
    if let reference = schema["$ref"] as? String {
      guard let resolved = try? resolve(reference, root: root, resolving: resolving)
      else { return false }
      return matches(
        instance: instance,
        schema: resolved.schema,
        root: root,
        resolving: resolved.resolving
      )
    }
    if let branches = schema["anyOf"] as? [Any] {
      return branches.compactMap { $0 as? [String: Any] }.contains {
        matches(instance: instance, schema: $0, root: root, resolving: resolving)
      }
    }
    guard let types = try? types(in: schema) else { return false }
    return types.contains { type in
      switch type {
      case "object": return instance is [String: Any]
      case "array": return instance is [Any]
      case "null": return instance is NSNull
      case "boolean": return instance is Bool
      case "integer": return instance is NSNumber && CFGetTypeID((instance as! NSNumber)) == CFNumberGetTypeID()
      case "number": return instance is NSNumber
      case "string": return instance is String
      default: return false
      }
    }
  }

  private static func validateSchema(
    _ schema: [String: Any],
    root: [String: Any],
    isRoot: Bool,
    resolving: Set<String>
  ) throws {
    let allowed: Set<String> = [
      "$comment", "$defs", "$id", "$ref", "$schema", "additionalProperties",
      "anyOf", "const", "description", "enum", "items", "minItems", "minLength",
      "minimum",
      "pattern", "properties", "required", "title", "type"
    ]
    guard schema.keys.allSatisfy({ allowed.contains($0) }) else {
      throw StrictJSONSchemaError.invalidSchema
    }
    if let definitions = schema["$defs"] {
      guard isRoot, let definitions = definitions as? [String: Any] else {
        throw StrictJSONSchemaError.invalidSchema
      }
      for definition in definitions.values {
        guard let definition = definition as? [String: Any] else {
          throw StrictJSONSchemaError.invalidSchema
        }
        try validateSchema(
          definition,
          root: root,
          isRoot: false,
          resolving: resolving
        )
      }
    }
    if let reference = schema["$ref"] {
      guard schema.count == 1, reference is String else {
        throw StrictJSONSchemaError.invalidSchema
      }
      _ = try resolve(reference as! String, root: root, resolving: resolving)
      return
    }
    if let branches = schema["anyOf"] {
      guard let branches = branches as? [Any], !branches.isEmpty else {
        throw StrictJSONSchemaError.invalidSchema
      }
      for branch in branches {
        guard let branch = branch as? [String: Any] else {
          throw StrictJSONSchemaError.invalidSchema
        }
        try validateSchema(
          branch,
          root: root,
          isRoot: false,
          resolving: resolving
        )
      }
      return
    }

    let schemaTypes = try types(in: schema)
    if schemaTypes.contains("object") {
      guard schema["additionalProperties"] as? Bool == false,
        let properties = schema["properties"] as? [String: Any]
      else {
        throw StrictJSONSchemaError.invalidSchema
      }
      for property in properties.values {
        guard let property = property as? [String: Any] else {
          throw StrictJSONSchemaError.invalidSchema
        }
        try validateSchema(
          property,
          root: root,
          isRoot: false,
          resolving: resolving
        )
      }
    }
    if schemaTypes.contains("array") {
      guard let items = schema["items"] as? [String: Any] else {
        throw StrictJSONSchemaError.invalidSchema
      }
      try validateSchema(items, root: root, isRoot: false, resolving: resolving)
    }
    if let required = schema["required"] {
      guard let required = required as? [Any], required.allSatisfy({ $0 is String })
      else { throw StrictJSONSchemaError.invalidSchema }
    }
    if let enumValues = schema["enum"], !(enumValues is [Any]) {
      throw StrictJSONSchemaError.invalidSchema
    }
    if let minItems = schema["minItems"], !(minItems is NSNumber) {
      throw StrictJSONSchemaError.invalidSchema
    }
    if let minLength = schema["minLength"], !(minLength is NSNumber) {
      throw StrictJSONSchemaError.invalidSchema
    }
    if let minimum = schema["minimum"], !(minimum is NSNumber) {
      throw StrictJSONSchemaError.invalidSchema
    }
    if let pattern = schema["pattern"], !(pattern is String) {
      throw StrictJSONSchemaError.invalidSchema
    }
    for key in ["$comment", "$id", "$schema", "description", "title"] {
      if let value = schema[key], !(value is String) {
        throw StrictJSONSchemaError.invalidSchema
      }
    }
  }

  private static func types(in schema: [String: Any]) throws -> Set<String> {
    guard let value = schema["type"] else {
      if schema["properties"] != nil || schema["items"] != nil {
        throw StrictJSONSchemaError.invalidSchema
      }
      return []
    }
    let values: [String]
    if let value = value as? String {
      values = [value]
    } else if let value = value as? [Any], value.allSatisfy({ $0 is String }) {
      values = value.compactMap { $0 as? String }
    } else {
      throw StrictJSONSchemaError.invalidSchema
    }
    guard !values.isEmpty, Set(values).isSubset(of: supportedTypes) else {
      throw StrictJSONSchemaError.invalidSchema
    }
    return Set(values)
  }

  private static func resolve(
    _ reference: String,
    root: [String: Any],
    resolving: Set<String>
  ) throws -> (schema: [String: Any], resolving: Set<String>) {
    let prefix = "#/$defs/"
    guard reference.hasPrefix(prefix), !reference.dropFirst(prefix.count).isEmpty,
      !resolving.contains(reference),
      let definitions = root["$defs"] as? [String: Any],
      let schema = definitions[String(reference.dropFirst(prefix.count))] as? [String: Any]
    else {
      throw StrictJSONSchemaError.invalidSchema
    }
    var next = resolving
    next.insert(reference)
    return (schema, next)
  }

  private static func escape(_ key: String) -> String {
    key.replacingOccurrences(of: "~", with: "~0")
      .replacingOccurrences(of: "/", with: "~1")
  }
}
