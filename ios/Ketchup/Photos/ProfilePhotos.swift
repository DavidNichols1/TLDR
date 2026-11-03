//
//  ProfilePhotos.swift
//  Ketchup
//
//  Your profile photo: pick it (PhotosPicker), frame it (AvatarCropper),
//  upload it into your own folder of the avatars bucket, then save its path
//  on your profile. The old photo is deleted once the new one is saved.
//  `.profilePhotoPicker(isPresented:)` runs the whole flow from any screen.
//

import SwiftUI
import PhotosUI

extension View {
    /// Set `isPresented` to pick a new profile photo. The photo picker opens,
    /// then the cropper, and the photo shows everywhere once it's saved.
    /// Needs AppModel in the environment.
    func profilePhotoPicker(isPresented: Binding<Bool>) -> some View {
        modifier(ProfilePhotoPicker(isPresented: isPresented))
    }
}

private struct ProfilePhotoPicker: ViewModifier {
    @Binding var isPresented: Bool

    @Environment(AppModel.self) private var app
    @State private var item: PhotosPickerItem?
    @State private var framing: Framing?
    @State private var problem: String?

    /// A picked photo on its way into the cropper.
    struct Framing: Identifiable {
        let id = UUID()
        let image: UIImage
    }

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $isPresented, selection: $item, matching: .images)
            .onChange(of: item) { _, picked in
                guard let picked else { return }
                item = nil
                Task { await open(picked) }
            }
            .fullScreenCover(item: $framing) { framing in
                AvatarCropper(image: framing.image) { jpeg in
                    try await ProfilePhotos.save(jpeg, app: app)
                }
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
              let image = await PhotoPrep.upright(data, maxPixels: 2048) else {
            problem = "Ketchup couldn't read it. Try another one."
            return
        }
        framing = Framing(image: image)
    }
}

/// Saving and removing your profile photo.
enum ProfilePhotos {

    /// Uploads a framed photo, points your profile at it, then deletes the
    /// one it replaces. The bytes go straight into the image cache, so the
    /// new photo shows everywhere without a download.
    static func save(_ jpeg: Data, app: AppModel) async throws {
        #if DEBUG
        if app.previewUser != nil {
            // Offline preview: keep it on the phone and pretend it saved.
            let object = StorageObject.avatar("preview/\(UUID().uuidString.lowercased()).jpg")
            RemoteImages.shared.store(jpeg, for: object)
            try await Task.sleep(for: .milliseconds(700))
            app.setAvatarPath(object.path)
            return
        }
        #endif
        guard let me = app.myId else { throw APIError.notSignedIn }
        // Lowercase: the folder must match auth.uid()::text (0006).
        let object = StorageObject.avatar("\(me.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg")
        try await Storage.upload(jpeg, to: object)
        RemoteImages.shared.store(jpeg, for: object)
        let old = app.me?.avatarPath
        do {
            try await setAvatarPath(object.path)
        } catch {
            Task { try? await Storage.remove([object]) }
            throw error
        }
        app.setAvatarPath(object.path)
        if let old, old != object.path { await discard(old) }
    }

    /// Back to your monogram: clears the path, then deletes the photo.
    static func remove(app: AppModel) async throws {
        guard let old = app.me?.avatarPath else { return }
        #if DEBUG
        if app.previewUser != nil {
            app.setAvatarPath(nil)
            return
        }
        #endif
        try await setAvatarPath(nil)
        app.setAvatarPath(nil)
        await discard(old)
    }

    private static func setAvatarPath(_ path: String?) async throws {
        guard let me = Supabase.shared.userId else { throw APIError.notSignedIn }
        let value: Any = path ?? NSNull()
        try await Supabase.shared.rest("PATCH", "/rest/v1/profiles",
                                       query: [.init(name: "id", value: "eq.\(me.uuidString)")],
                                       body: JSONSerialization.data(withJSONObject: ["avatar_path": value]))
    }

    /// Best effort: a photo left behind only costs storage.
    private static func discard(_ path: String) async {
        let object = StorageObject.avatar(path)
        try? await Storage.remove([object])
        RemoteImages.shared.forget(object)
    }
}

/// Getting a picked photo ready to frame or send.
enum PhotoPrep {
    /// The picked file decoded upright, its long side capped at `maxPixels`,
    /// off the main thread, so a 48 MP original never sits in memory.
    nonisolated static func upright(_ data: Data, maxPixels: Int) async -> UIImage? {
        RemoteImages.decode(data, maxPixels: maxPixels)
    }
}
