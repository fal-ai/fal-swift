import Foundation

extension Client {
    func sendRequest(_ urlString: String, input: Data?, queryParams: [String: Any]? = nil, options: RunOptions) async throws -> Data {
        guard var url = URL(string: urlString) else {
            throw FalError.invalidUrl(url: urlString)
        }

        if let queryParams,
           var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            urlComponents.queryItems = queryParams.map {
                URLQueryItem(name: $0.key, value: String(describing: $0.value))
            }
            url = urlComponents.url ?? url
        }

        if let requestProxy = config.requestProxy {
            guard let proxyUrl = URL(string: requestProxy) else {
                throw FalError.invalidUrl(url: requestProxy)
            }
            url = proxyUrl
        }

        var request = URLRequest(url: url)
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
            request.setValue(urlString, forHTTPHeaderField: "x-fal-target-url")
        }

        if input != nil, options.httpMethod != .get {
            request.httpBody = input
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    var userAgent: String {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return "fal.ai/swift-client 0.1.0 - \(osVersion)"
    }
}
