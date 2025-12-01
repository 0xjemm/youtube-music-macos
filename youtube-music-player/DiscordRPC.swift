import Foundation

@MainActor
class DiscordRPC {
    private let clientId = Secrets.discordClientId

    private var socket: Int32 = -1
    private var isConnected = false

    init() {
        connect()
    }

    deinit {
        if socket >= 0 {
            Darwin.close(socket)
        }
    }

    func connect() {
        guard !isConnected else { return }

        var socketPaths = ["/tmp/discord-ipc-0", "/var/tmp/discord-ipc-0"]

        let fileManager = FileManager.default
        if let enumerator = fileManager.enumerator(atPath: "/var/folders") {
            while let path = enumerator.nextObject() as? String {
                if path.hasSuffix("discord-ipc-0") {
                    socketPaths.insert("/var/folders/\(path)", at: 0)
                    break
                }
                if path.components(separatedBy: "/").count > 4 {
                    enumerator.skipDescendants()
                }
            }
        }

        var buffer = [CChar](repeating: 0, count: 1024)
        confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        let darwinTmp = String(cString: buffer)
        if !darwinTmp.isEmpty {
            socketPaths.insert("\(darwinTmp)discord-ipc-0", at: 0)
        }

        for path in socketPaths {
            socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
            if socket < 0 { continue }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)

            let pathBytes = path.utf8CString
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 104) { sunPath in
                    for (i, byte) in pathBytes.enumerated() where i < 104 {
                        sunPath[i] = byte
                    }
                }
            }

            let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let result = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    Darwin.connect(socket, sockaddrPtr, addrLen)
                }
            }

            if result == 0 {
                isConnected = true
                handshake()
                return
            } else {
                Darwin.close(socket)
            }
        }
    }

    private func handshake() {
        let payload: [String: Any] = [
            "v": 1,
            "client_id": clientId
        ]

        send(opcode: 0, payload: payload)

        let sock = socket
        Task.detached {
            Self.readResponse(socket: sock)
        }
    }

    nonisolated private static func readResponse(socket: Int32) {
        var header = [UInt8](repeating: 0, count: 8)
        let headerRead = Darwin.recv(socket, &header, 8, 0)

        if headerRead == 8 {
            let length = Int(header[4]) | (Int(header[5]) << 8) | (Int(header[6]) << 16) | (Int(header[7]) << 24)
            var body = [UInt8](repeating: 0, count: length)
            _ = Darwin.recv(socket, &body, length, 0)
        }
    }

    func updatePresence(title: String, artist: String, artworkUrl: String?) {
        if !isConnected {
            connect()
        }
        guard isConnected else { return }

        var assets: [String: Any] = [:]
        if let artwork = artworkUrl, !artwork.isEmpty {
            assets["large_image"] = artwork
            assets["large_text"] = title
        }

        let activity: [String: Any] = [
            "details": title,
            "state": "by \(artist)",
            "timestamps": [
                "start": Int(Date().timeIntervalSince1970 * 1000)
            ],
            "assets": assets
        ]

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "activity": activity
            ],
            "nonce": UUID().uuidString
        ]

        send(opcode: 1, payload: payload)
    }

    func clearPresence() {
        guard isConnected else { return }

        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "activity": NSNull()
            ],
            "nonce": UUID().uuidString
        ]

        send(opcode: 1, payload: payload)
    }

    private func send(opcode: UInt32, payload: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }

        let length = UInt32(jsonData.count)
        var header = [UInt8](repeating: 0, count: 8)

        header[0] = UInt8(opcode & 0xFF)
        header[1] = UInt8((opcode >> 8) & 0xFF)
        header[2] = UInt8((opcode >> 16) & 0xFF)
        header[3] = UInt8((opcode >> 24) & 0xFF)

        header[4] = UInt8(length & 0xFF)
        header[5] = UInt8((length >> 8) & 0xFF)
        header[6] = UInt8((length >> 16) & 0xFF)
        header[7] = UInt8((length >> 24) & 0xFF)

        var message = header
        message.append(contentsOf: jsonData)

        Darwin.send(socket, message, message.count, 0)
    }

    func disconnect() {
        if socket >= 0 {
            Darwin.close(socket)
            socket = -1
        }
        isConnected = false
    }
}
