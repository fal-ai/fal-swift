

func isLegacyFormat(id: String) -> Bool {
    let legacyFormat = "^(\\d+)-([a-zA-Z0-9-]+)$"
    return id.range(of: legacyFormat, options: .regularExpression) != nil
}

func buildUrl(fromId id: String, path: String? = nil) -> String {
    if isLegacyFormat(id: id) {
        return "https://\(id).gateway.alpha.fal.ai" + (path ?? "")
    }
    return "https://fal.run/\(id)" + (path ?? "")
}
