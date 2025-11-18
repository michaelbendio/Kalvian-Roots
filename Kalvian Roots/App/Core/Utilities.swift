import Foundation

// MARK: - JSON Pretty Printing Helpers

/// Pretty-print JSON from Data. Returns a human-readable string or an error description.
internal func prettyJSON(_ data: Data, sortedKeys: Bool = true) -> String {
    do {
        let object = try JSONSerialization.jsonObject(with: data)
        let options: JSONSerialization.WritingOptions = sortedKeys ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted]
        let prettyData = try JSONSerialization.data(withJSONObject: object, options: options)
        return String(data: prettyData, encoding: .utf8) ?? "<non-UTF8 data>"
    } catch {
        return "JSON error: \(error)"
    }
}

/// Pretty-print JSON from a String. Returns a human-readable string or an error description.
internal func prettyJSON(_ jsonString: String, sortedKeys: Bool = true) -> String {
    guard let data = jsonString.data(using: .utf8) else { return "<not UTF-8>" }
    return prettyJSON(data, sortedKeys: sortedKeys)
}

/// Pretty-print JSON from Any (Dictionary/Array). Falls back to description if not JSON-serializable.
internal func prettyJSON(_ value: Any, sortedKeys: Bool = true) -> String {
    if let data = value as? Data { return prettyJSON(data, sortedKeys: sortedKeys) }
    if let string = value as? String { return prettyJSON(string, sortedKeys: sortedKeys) }
    if JSONSerialization.isValidJSONObject(value) {
        do {
            let options: JSONSerialization.WritingOptions = sortedKeys ? [.prettyPrinted, .sortedKeys] : [.prettyPrinted]
            let data = try JSONSerialization.data(withJSONObject: value, options: options)
            return String(data: data, encoding: .utf8) ?? "<non-UTF8 data>"
        } catch {
            return "JSON error: \(error)"
        }
    }
    return String(describing: value)
}

/// Convenience: print a pretty JSON representation to the console.
@discardableResult
internal func debugPrettyJSON(_ value: Any, label: String? = nil) -> String {
    let output = prettyJSON(value)
    if let label = label {
        print("\(label):\n\(output)")
    } else {
        print(output)
    }
    return output
}
