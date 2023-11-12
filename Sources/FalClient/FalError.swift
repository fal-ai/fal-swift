
enum FalError: Error {
    case invalidResultFormat
    case invalidUrl(url: String)
    case unauthorized(message: String)
    case queueTimeout
}
