import Foundation

/// Newline-delimited JSON framing for the daemon socket.
///
/// A socket hands over arbitrary chunks, so messages arrive split and glued together.
/// This buffers until a newline and only then decodes.
public struct NDJSONDecoderBuffer {
    private var buffer = Data()
    private let decoder = JSONDecoder()
    /// Guards against a peer that never sends a newline.
    public let maxMessageBytes: Int

    public init(maxMessageBytes: Int = 8 * 1024 * 1024) {
        self.maxMessageBytes = maxMessageBytes
    }

    public enum BufferError: Error { case messageTooLarge }

    /// Appends a chunk and returns every complete message it now contains.
    public mutating func append<T: Decodable>(_ chunk: Data, as type: T.Type) throws -> [T] {
        buffer.append(chunk)
        if buffer.count > maxMessageBytes, !buffer.contains(UInt8(ascii: "\n")) {
            buffer.removeAll(keepingCapacity: false)
            throw BufferError.messageTooLarge
        }
        var messages: [T] = []
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            guard !line.isEmpty else { continue }
            // A single unreadable line must not poison the rest of the stream.
            if let message = try? decoder.decode(T.self, from: Data(line)) {
                messages.append(message)
            }
        }
        buffer = Data(buffer)
        return messages
    }
}

public enum NDJSONEncoder {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
