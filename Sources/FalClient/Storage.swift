import Foundation

public enum FileType {
    case custom(String)

    public static var imagePng: Self { .custom("image/png") }
    public static var imageJpeg: Self { .custom("image/jpeg") }
    public static var imageWebp: Self { .custom("image/webp") }
    public static var imageGif: Self { .custom("image/gif") }
    public static var videoMp4: Self { .custom("video/mp4") }
    public static var videoMpeg: Self { .custom("video/mpeg") }
    public static var audioMp3: Self { .custom("audio/mp3") }
    public static var audioMpeg: Self { .custom("audio/mpeg") }
    public static var audioWav: Self { .custom("audio/wav") }
    public static var audioOgg: Self { .custom("audio/ogg") }
    public static var audioWebm: Self { .custom("audio/webm") }
    public static var applicationStream: Self { .custom("application/octet-stream") }

    public var mimeType: String {
        switch self {
        case let .custom(type):
            return type
        }
    }

    public var fileExtension: String {
        guard case let .custom(type) = self else {
            return "bin"
        }
        if type == FileType.applicationStream.mimeType {
            return "bin"
        }
        return String(type.split(separator: "/").last ?? "bin")
    }
}

public protocol Storage {
    var client: Client { get }

    func upload(data: Data, ofType type: FileType) async throws -> String
}

public extension Storage {
    func upload(data: Data, ofType type: FileType = .applicationStream) async throws -> String {
        try await upload(data: data, ofType: type)
    }
}

struct UploadUrl: Codable {
    let fileUrl: String
    let uploadUrl: String

    enum CodingKeys: String, CodingKey {
        case fileUrl = "file_url"
        case uploadUrl = "upload_url"
    }
}

struct StorageClient: Storage {
    let client: Client

    func autoUpload(input: any Encodable) async throws -> Payload {
        var transformedInput: Payload = .dict([:])
        if case let .dict(inputDict) = input as? Payload {
            for (key, value) in inputDict {
                if case let .data(data) = value {
                    transformedInput[key] = try await .string(upload(data: data))
                } else {
                    transformedInput[key] = value
                }
            }
        } else {
            // TODO: support encodable types that are not Payload
            print("Warning: autoUpload is not yet supported on custom Encodable types")
//            let mirror = Mirror(reflecting: input)
//            for child in mirror.children {
//                if let data = child.value as? Data {
//                    transformedInput[child.label ?? ""] = .string(try await upload(data: data))
//                } else {
//                    transformedInput[child.label ?? ""] = child.value
//                }
//            }
        }
        return transformedInput
    }

    func initiateUpload(data _: Data, ofType type: FileType) async throws -> UploadUrl {
        let input: Payload = [
            "content_type": .string(type.mimeType),
            "file_name": .string("\(UUID().uuidString).\(type.fileExtension)"),
        ]
        let response = try await client.sendRequest(
            to: "https://rest.alpha.fal.ai/storage/upload/initiate",
            input: input.json(),
            options: .withMethod(.post)
        )
        return try JSONDecoder().decode(UploadUrl.self, from: response)
    }

    func upload(data: Data, ofType type: FileType) async throws -> String {
        let uploadUrl = try await initiateUpload(data: data, ofType: type)

        // Upload the file to the upload URL.
        // Here we use URLSession directly instead of the client to avoid going
        // through the proxy, we need to hit the blob url directly.
        var request = URLRequest(url: URL(string: uploadUrl.uploadUrl)!)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(type.mimeType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        let (data, response) = try await URLSession.shared.data(for: request)
        try client.checkResponseStatus(for: response, withData: data)

        return uploadUrl.fileUrl
    }
}
