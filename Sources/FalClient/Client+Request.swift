import Foundation

extension HTTPURLResponse {
    /// Returns `true` if `statusCode` is in range 200...299.
    /// Otherwise `false`.
    var isSuccessful: Bool {
        200 ... 299 ~= statusCode
    }
}

extension Client {
    func sendRequest(to urlString: String, input: Data?, queryParams: [String: Any]? = nil, options: RunOptions) async throws -> Data {
        guard var url = URL(string: urlString) else {
            throw FalError.invalidUrl(url: urlString)
        }

        if let queryParams,
           !queryParams.isEmpty,
           var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            urlComponents.queryItems = queryParams.map {
                URLQueryItem(name: $0.key, value: String(describing: $0.value))
            }
            url = urlComponents.url ?? url
        }

        let targetUrl = url
        if let requestProxy = config.requestProxy {
            guard let proxyUrl = URL(string: requestProxy) else {
                throw FalError.invalidUrl(url: requestProxy)
            }
            url = proxyUrl
        }

        var request = URLRequest(url: url)
        if let header = config.customHeaders {
            for (key, value) in header {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        request.httpMethod = options.httpMethod.rawValue.uppercased()
        request.setValue("application/json", forHTTPHeaderField: "accept")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(userAgent, forHTTPHeaderField: "user-agent")

        // setup credentials if available
        let credentials = config.credentials.description
        if !credentials.isEmpty {
            request.setValue("Key \(config.credentials.description)", forHTTPHeaderField: "authorization")
        }

        // setup the request proxy if available
        if config.requestProxy != nil {
            request.setValue(targetUrl.absoluteString, forHTTPHeaderField: "x-fal-target-url")
        }

        if input != nil, options.httpMethod != .get {
            request.httpBody = input
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkResponseStatus(for: response, withData: data)
        return data
    }

    func checkResponseStatus(for response: URLResponse, withData data: Data) throws {
        guard response is HTTPURLResponse else {
            throw FalError.invalidResultFormat
        }
        if let httpResponse = response as? HTTPURLResponse, !httpResponse.isSuccessful {
            let errorPayload = try? Payload.create(fromJSON: data)
            let statusCode = httpResponse.statusCode
            let message = errorPayload?["detail"].stringValue
                ?? errorPayload?.stringValue
                ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
            throw FalError.httpError(
                status: statusCode,
                message: message,
                payload: errorPayload
            )
        }
    }

    var userAgent: String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return "fal.ai/swift-client 0.1.0 - \(osVersion)"
    }
}
