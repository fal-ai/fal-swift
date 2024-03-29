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
    try AppId.parse(id: id).appAlias
}

struct AppId {
    let ownerId: String
    let appAlias: String
    let path: String?

    static func parse(id: String) throws -> Self {
        let appId = try ensureAppIdFormat(id)
        let parts = appId.components(separatedBy: "/")
        guard parts.count > 1 else {
            throw FalError.invalidAppId(id: id)
        }
        return Self(
            ownerId: parts[0],
            appAlias: parts[1],
            path: parts.endIndex > 2 ? parts.dropFirst(2).joined(separator: "/") : nil
        )
    }
}
