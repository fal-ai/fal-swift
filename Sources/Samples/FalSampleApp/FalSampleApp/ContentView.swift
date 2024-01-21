import Kingfisher
import SwiftUI

let PROMPT = "a city landscape of a cyberpunk metropolis, raining, purple, pink and teal neon lights, highly detailed, uhd"

struct ContentView: View {
    @State private var imageUrl: String?
    @State private var isLoading: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            if isLoading {
                ProgressView("Loading...")
            } else {
                Button("Generate Image") {
                    Task {
                        print("Generate image...")
                        isLoading = true
                        do {
                            let result = try await fal.subscribe(
                                to: "fal-ai/fast-sdxl",
                                input: [
                                    "prompt": .string(PROMPT),
                                ],
                                includeLogs: true
                            ) { update in
                                update.logs
                                    .filter { log in !log.message.isEmpty }
                                    .forEach { log in
                                        print(log.message)
                                    }
                            }
                            isLoading = false
                            if case let .string(url) = result["images"][0]["url"] {
                                imageUrl = url
                            }
                        } catch {
                            print(error)
                            isLoading = false
                        }
                    }
                }
                .padding()
                .cornerRadius(16)
                .foregroundColor(.white)
                .background(Color.indigo)
            }

            if let imageUrl {
                KFImage.url(URL(string: imageUrl)!)
                    .fade(duration: 0.25)
                    .resizable()
                    .aspectRatio(1, contentMode: .fill)
                    .padding()
            }
        }
        .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
