import Foundation

func buildUrl(fromId id: String, path: String? = nil, subdomain: String? = nil) -> String {
    let appId = (try? ensureAppIdFormat(id)) ?? id
    let sub = subdomain != nil ? "\(subdomain!)." : ""
    return "https://\(sub)fal.run/\(appId)" + (path ?? "")
}

func ensureAppIdFormat(_ id: String) throws -> String {
    let parts = id.split(separator: "/")
    if parts.count > 1 {
        return id
    }
    let regex = try NSRegularExpression(pattern: "^([0-9]+)-([a-zA-Z0-9-]+)$")
    let matches = regex.matches(in: id, options: [], range: NSRange(location: 0, length: id.utf16.count))
    if let match = matches.first, match.numberOfRanges == 3,
       let appOwnerRange = Range(match.range(at: 1), in: id),
       let appIdRange = Range(match.range(at: 2), in: id)
    {
        let appOwner = String(id[appOwnerRange])
        let appId = String(id[appIdRange])
        return "\(appOwner)/\(appId)"
    }
    return id
}

func appAlias(fromId id: String) throws -> String {
    let appId = try ensureAppIdFormat(id)
    guard let alias = appId.split(separator: "/").dropFirst().first else {
        throw FalError.invalidUrl(url: id)
    }
    return String(describing: alias)
}
