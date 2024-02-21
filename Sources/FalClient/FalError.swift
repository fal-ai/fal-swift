
enum FalError: Error {
    case httpError(status: Int, message: String, payload: Payload?)
    case invalidResultFormat
    case invalidUrl(url: String)
    case unauthorized(message: String)
    case queueTimeout
    case invalidAppId(id: String)
}
