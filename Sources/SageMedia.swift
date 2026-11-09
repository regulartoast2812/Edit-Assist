import Foundation

/// Sage's media tools (2026-11-09, from the Vault Agent plugin): Fetch media downloads the social videos and pictures a
/// note links to into the vault's attachments, puts an embed where each link was and uses the video's thumbnail as the
/// note's banner; Transcribe writes a "## Transcript" under the note's source, transcribed on this Mac with WhisperX.
///
/// The interface the rest of Sage calls. Its bodies are filled in by the media port; until then they say so.
enum SageMedia {
    /// What a run did, for the chat: each line said to you, and the files it made or changed (paths in the vault).
    struct Report: Equatable {
        var lines: [String] = []
        var changed: [String] = []
    }

    /// Downloads and localizes the media the note links to. `progress` is told each step as it happens.
    static func fetch(note: URL, vault: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Report {
        throw AssistError.message(L("Fetch media isn't built yet."))
    }

    /// Transcribes the note's video or audio (its source, or media embedded in it) and writes the transcript into the note.
    static func transcribe(note: URL, vault: URL, progress: @escaping @Sendable (String) -> Void) async throws -> Report {
        throw AssistError.message(L("Transcribe isn't built yet."))
    }
}
