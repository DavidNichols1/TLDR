//
//  ChatPhotos.swift
//  Ketchup
//
//  Photos sent in a chat. Each photo goes up as two JPEGs in the private
//  chat-media bucket, named after the message: "<chat>/<message>.jpg", at
//  most 2048 px, for the viewer, and "<chat>/<message>_small.jpg", 768 px,
//  for the thread (and for Muse Spark). Both are re-encoded from pixels, so
//  no location or other metadata leaves the phone. The bytes go into the
//  image cache first, so the bubble shows the photo before it's uploaded;
//  the message row goes in only once both files are up
//  (supabase/migrations/0006_photos.sql, part 2).
//

import SwiftUI
import PhotosUI

// MARK: - Messages with photos

extension Message {
    /// The photo, full size (the viewer).
    var photo: StorageObject? {
        imagePath.map { StorageObject(bucket: Storage.chatMedia, path: $0) }
    }

    /// The 768 px copy next to it (the thread, Muse Spark).
    var smallPhoto: StorageObject? {
        imagePath.map { StorageObject(bucket: Storage.chatMedia, path: ChatPhotos.smallPath(for: $0)) }
    }

    /// What a line about this message says: its words, or "Photo" for a
    /// photo sent without any.
    var previewText: String {
        imagePath != nil && body.isEmpty ? "Photo" : body
    }
}

enum ChatPhotos {
    /// Where a message's photo goes: its chat's folder, named for the message.
    static func path(chat: UUID, message: UUID) -> String {
        "\(chat.uuidString.lowercased())/\(message.uuidString.lowercased()).jpg"
    }

    nonisolated static func smallPath(for path: String) -> String {
        path.hasSuffix(".jpg") ? String(path.dropLast(4)) + "_small.jpg" : path + "_small"
    }

    /// Account deletion: every chat photo you sent and your profile photo,
    /// through the Storage API (deleting rows with SQL would leave the files
    /// behind). Call it before `delete_account()`; best effort.
    static func deleteMine(app: AppModel) async {
        guard let me = app.myId, app.previewUser == nil else { return }
        if let avatar = app.me?.avatarPath {
            try? await Storage.remove([.avatar(avatar)])
        }
        guard let data = try? await Supabase.shared.rest("GET", "/rest/v1/messages", query: [
            .init(name: "sender", value: "eq.\(me.uuidString)"),
            .init(name: "image_path", value: "not.is.null"),
            .init(name: "select", value: "image_path"),
            .init(name: "limit", value: "5000"),
        ]) else { return }
        struct Row: Decodable { let image_path: String }
        let paths = ((try? JSONDecoder().decode([Row].self, from: data)) ?? []).map(\.image_path)
        let files = paths.flatMap { [StorageObject(bucket: Storage.chatMedia, path: $0),
                                     StorageObject(bucket: Storage.chatMedia, path: smallPath(for: $0))] }
        // The API takes up to 1,000 names a call.
        for start in stride(from: 0, to: files.count, by: 500) {
            try? await Storage.remove(Array(files[start..<min(start + 500, files.count)]))
        }
    }
}

// MARK: - Getting a photo ready

/// A picked photo, ready to send: two JPEGs and the full one's size.
nonisolated struct PreparedPhoto: Sendable {
    /// At most 2048 px on the long side.
    let full: Data
    /// At most 768 px on the long side.
    let small: Data
    let width: Int
    let height: Int
    /// What the composer shows while it waits to go.
    let preview: UIImage
}

extension PhotoPrep {
    nonisolated static let fullPixels = 2048
    nonisolated static let smallPixels = 768

    /// Both copies of a picked photo, upright and re-encoded off the main
    /// thread. Nil if the file isn't a photo ImageIO can read.
    @concurrent nonisolated static func prepare(_ data: Data) async -> PreparedPhoto? {
        prepared(data)
    }

    /// The same, right here (offline previews draw theirs this way).
    nonisolated static func prepared(_ data: Data) -> PreparedPhoto? {
        guard let full = RemoteImages.decode(data, maxPixels: fullPixels),
              let small = RemoteImages.decode(data, maxPixels: smallPixels),
              let fullJPEG = full.jpegData(compressionQuality: 0.8),
              let smallJPEG = small.jpegData(compressionQuality: 0.72),
              let size = full.cgImage.map({ (width: $0.width, height: $0.height) }) else { return nil }
        return PreparedPhoto(full: fullJPEG, small: smallJPEG, width: size.width, height: size.height, preview: small)
    }
}

// MARK: - Uploading

/// Photos on their way up: the files waiting for each pending message, and
/// how far along each one is. A retry carries on where the last try stopped.
@Observable
final class PhotoUploads {
    static let shared = PhotoUploads()

    /// 0...1 per pending message while its files upload.
    private(set) var progress: [UUID: Double] = [:]

    private struct Waiting {
        let photo: PreparedPhoto
        var smallDone = false
        var fullDone = false
    }

    @ObservationIgnored private var waiting: [UUID: Waiting] = [:]

    /// Keeps a photo for its pending message, and puts both copies in the
    /// image cache under their final names, so the bubble draws it now.
    func hold(_ photo: PreparedPhoto, for message: Message) {
        guard let full = message.photo, let small = message.smallPhoto else { return }
        waiting[message.id] = Waiting(photo: photo)
        RemoteImages.shared.store(photo.full, for: full)
        RemoteImages.shared.store(photo.small, for: small)
    }

    /// Uploads whatever of this message's photo isn't up yet: the small copy
    /// first (it's what the thread shows), then the full one.
    func upload(for message: Message, previewing: Bool = false) async throws {
        guard let full = message.photo, let small = message.smallPhoto else { return }
        guard let item = waiting[message.id] else {
            throw APIError.server("That photo is no longer on this phone. Pick it again.")
        }
        let id = message.id
        progress[id] = progress[id] ?? 0
        if previewing {
            try await rehearse(id)
            return
        }
        // The small copy is about a sixth of the bytes.
        if !item.smallDone {
            try await Storage.upload(item.photo.small, to: small) { [self] done in
                Task { @MainActor in self.report(id, done * 0.15) }
            }
            waiting[id]?.smallDone = true
        }
        if !item.fullDone {
            try await Storage.upload(item.photo.full, to: full) { [self] done in
                Task { @MainActor in self.report(id, 0.15 + done * 0.85) }
            }
            waiting[id]?.fullDone = true
        }
        report(id, 1)
    }

    /// The message is in: let its files go.
    func finished(_ id: UUID) {
        waiting[id] = nil
        progress[id] = nil
    }

    private func report(_ id: UUID, _ value: Double) {
        guard waiting[id] != nil else { return }
        progress[id] = max(progress[id] ?? 0, value)
    }

    #if DEBUG
    /// Offline previews: how long a pretend upload takes.
    @ObservationIgnored var previewDuration: Duration = .seconds(2)
    #endif

    /// Offline preview: the progress ring fills with nothing sent.
    private func rehearse(_ id: UUID) async throws {
        #if DEBUG
        let steps = 20
        for step in 1...steps {
            try await Task.sleep(for: previewDuration / steps)
            report(id, Double(step) / Double(steps))
        }
        #endif
    }
}

// MARK: - Picking

extension View {
    /// Set `isPresented` to pick a photo for a chat. `onPicked` gets it ready
    /// to send (both copies made), or the picker says why it couldn't.
    func chatPhotoPicker(isPresented: Binding<Bool>, onPicked: @escaping (PreparedPhoto) -> Void) -> some View {
        modifier(ChatPhotoPicker(isPresented: isPresented, onPicked: onPicked))
    }
}

private struct ChatPhotoPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPicked: (PreparedPhoto) -> Void

    @State private var item: PhotosPickerItem?
    @State private var problem: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                item = nil
                Task { await open(picked) }
            }
            .alert("Couldn't open that photo", isPresented: Binding(get: { problem != nil },
                                                                     set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
    }

    private func open(_ picked: PhotosPickerItem) async {
        guard let data = try? await picked.loadTransferable(type: Data.self),
              let photo = await PhotoPrep.prepare(data) else {
            problem = "Ketchup couldn't read it. Try another one."
            return
        }
        onPicked(photo)
    }
}
