## The fal.ai Swift Client

![FalClient Swift package](https://img.shields.io/badge/swift-package-brightgreen)
![Build](https://img.shields.io/badge/build-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

## About the Project

The `FalClient` is a robust and user-friendly Swift package designed for seamless integration of fal serverless functions into Swift projects. This library, developed in pure Swift, provides developers with simple APIs to interact with AI models, suitable for both iOS and macOS platforms.

## Getting Started

The `FalClient` library serves as a client for fal serverless Python functions. Before using this library, ensure you've set up your serverless functions as per the [quickstart guide](https://fal.ai/docs).

### Client Library

This Swift client library is crafted as a lightweight layer atop Swift's networking standards like `URLSession`. It ensures hassle-free integration into your existing Swift codebase. The library is designed to address the nuances of Swift and Apple's ecosystem, ensuring smooth operation across different Apple platforms.

> **Note:**
> Make sure to review the [fal-serverless getting started guide](https://fal.ai/docs) to acquire your credentials and register your functions.

1. Add `FalClient` as a dependency in your Swift Package Manager.

2. Set up the client instance:
   ```swift
   import FalClient
   let fal = FalClient.withCredentials(.keyPair("FAL_KEY_ID:FAL_KEY_SECRET"))

   // You can also use a proxy to protect your credentials
   // let fal = FalClient.withProxy("http://localhost:3333/api/fal/proxy")
   ```

3. Use `fal.subscribe` to dispatch requests to the model API:
   ```swift
   let result = try await fal.subscribe(to: "text-to-image",
       input: [
           "prompt": "a cute shih-tzu puppy",
           "model_name": "stabilityai/stable-diffusion-xl-base-1.0",
           "image_size": "square_hd"
       ]) { update in
           print(update)
       }
   ```

**Notes:**

- Replace `text-to-image` with a valid model id. Check [fal.ai/models](https://fal.ai/models) for all available models.
- It fully relies on `async/await` for asynchronous programming.
- The result type in Swift will be a `[String: Any]` and the entries depend on the API output schema.
- The Swift client also supports typed inputs and outputs through `Codable`.

## Real-time 

The client supports real-time model APIs. Checkout the [FalRealtimeSampleApp](./Sources/Samples/FalRealtimeSampleApp/) for more details.

```swift
let connection = try fal.realtime.connect(
    to: OptimizedLatentConsistency,
    connectionKey: "PencilKitDemo",
    throttleInterval: .milliseconds(128)
) { (result: Result<LcmResponse, Error>)  in
    if case let .success(data) = result,
        let image = data.images.first {
        let data = try? Data(contentsOf: URL(string: image.url)!)
        DispatchQueue.main.async {
            self.currentImage = data
        }
    }
}

try connection.send(LcmInput(
    prompt: prompt,
    imageUrl: "data:image/jpeg;base64,\(drawing.base64EncodedString())",
    seed: 6_252_023,
    syncMode: true
))
```

## Sample apps

Check the `Sources/Samples` folder for a handful of sample applications using the `FalClient`.

Open them with `xed` to quickly start playing with 

```bash
xed Sources/Sample/FalSampleApp
```

## Roadmap

See the [open feature requests](https://github.com/fal-ai/serverless-client-swift/labels/enhancement) for a list of proposed features and join the discussion.

## Contributing

Contributions are what make the open source community such an amazing place to learn, inspire, and create. Any contributions you make to the Swift version of the client are **greatly appreciated**.

## License

Distributed under the MIT License. See [LICENSE](https://github.com/fal-ai/serverless-client-swift/blob/main/LICENSE) for more information.
