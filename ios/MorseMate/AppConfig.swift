import Foundation

/// App configuration.
///
/// The app holds **no API secret**. It fetches a short-lived join token from the
/// MorseMate dev token server (`agent/token_server.py`), which mints tokens from
/// the backend `.env` credentials. See `../README.md`.
enum AppConfig {
    /// Base URL of the running token server (`agent/token_server.py`).
    ///
    /// - **Simulator:** leave as `http://localhost:8080` — works out of the box.
    /// - **Physical device:** change to `http://<your-Mac-LAN-IP>:8080`. The token
    ///   server prints the exact URL to use ("Device: …") when it starts. The Mac
    ///   and iPhone must be on the same Wi-Fi network.
    static let tokenServerURL = "http://localhost:8080"

    /// Display name for this participant in the room.
    static let participantName = "ios-student"
}
