import Foundation

enum SessionRefreshSignal {
    private static let notificationName = Notification.Name("com.clockbar.104.session.refresh-request")

    static func post() {
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    static func subscribe(handler: @escaping () -> Void) -> Token {
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { _ in handler() }
        return Token(observer: observer)
    }

    final class Token {
        private let observer: NSObjectProtocol
        fileprivate init(observer: NSObjectProtocol) { self.observer = observer }
        deinit { DistributedNotificationCenter.default().removeObserver(observer) }
    }
}
