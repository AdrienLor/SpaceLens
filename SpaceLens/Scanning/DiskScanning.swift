import Foundation

protocol DiskScanning: Sendable {
    /// Produces ordered progress events and exactly one terminal completion event.
    /// Cancelling the consuming task must stop traversal and prevent later events.
    func scan(
        _ root: URL,
        options: ScanOptions
    ) -> AsyncThrowingStream<ScanEvent, Error>
}
