@testable import FalClient
import Nimble
import Quick

class UtilitySpec: QuickSpec {
    override static func spec() {
        describe("Utility.buildUrl") {
            it("should create a url to gateway fal.ai from a legacy app alias") {
                let id = "1234-app-alias"
                let url = buildUrl(fromId: id)
                expect(url).to(equal("https://\(id).gateway.alpha.fal.ai"))
            }
            it("should create a url to fal.run from an app alias") {
                let id = "user/app-alias"
                let url = buildUrl(fromId: id)
                expect(url).to(equal("https://fal.run/user/app-alias"))
            }
        }
    }
}
