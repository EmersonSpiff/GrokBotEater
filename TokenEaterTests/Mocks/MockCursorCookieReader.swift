import Foundation
@testable import GrokBotEaterApp

final class MockCursorCookieReader: CursorCookieReaderProtocol {
    var cookieToReturn: String?
    
    func readCookie() -> String? {
        cookieToReturn
    }
}
