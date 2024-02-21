@testable import FalClient
import Nimble
import Quick

class UtilitySpec: QuickSpec {
    override static func spec() {
        describe("Utility.buildUrl") {
            it("should create a url to gateway fal.ai from a legacy app alias") {
                let id = "1234-app-alias"
                let url = buildUrl(fromId: id)
                expect(url).to(equal("https://fal.run/1234/app-alias"))
            }
            it("should create a url to fal.run from an app alias") {
                let id = "user/app-alias"
                let url = buildUrl(fromId: id)
                expect(url).to(equal("https://fal.run/user/app-alias"))
            }
        }
        describe("Utility.AppId.parse") {
            it ("should parse an id without a path") {
                let appId = try AppId.parse(id: "fal-ai/fast-sdxl")
                expect(appId.ownerId).to(equal("fal-ai"))
                expect(appId.appAlias).to(equal("fast-sdxl"))
                expect(appId.path).to(beNil())
            }
            it ("should parse an id with a path") {
                let appId = try AppId.parse(id: "fal-ai/fast-sdxl/image-to-image")
                expect(appId.ownerId).to(equal("fal-ai"))
                expect(appId.appAlias).to(equal("fast-sdxl"))
                expect(appId.path).to(equal("image-to-image"))
            }
        }
    }
}
