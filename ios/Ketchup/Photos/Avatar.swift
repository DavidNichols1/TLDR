//
//  Avatar.swift
//  Ketchup
//
//  A person's profile photo wherever a person shows: sender runs in a chat,
//  a chat's members, the inbox's account button.
//

import SwiftUI

/// A person's profile photo in Monogram's rounded square, with a hairline so
/// it sits on the paper like a print. Their Monogram stands in when they have
/// no photo, while it loads, and if it can't load. Decorative, like Monogram:
/// say the name beside it. Pass a `size` from `@ScaledMetric` where text sits
/// beside it.
struct Avatar: View {
    let name: String
    /// The photo's path in the avatars bucket (`profiles.avatar_path`).
    var path: String?
    var color: Color?
    var size: CGFloat

    init(name: String, path: String?, color: Color? = nil, size: CGFloat = 36) {
        self.name = name
        self.path = path
        self.color = color
        self.size = size
    }

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        RemoteImage(object: path.map(StorageObject.avatar),
                    pixels: RemoteImages.pixels(points: size, scale: displayScale)) { image in
            image
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay { shape.strokeBorder(Theme.rule, lineWidth: 1) }
        } placeholder: { _ in
            Monogram(name: name, color: color, size: size)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension ChatModel {
    /// A member's profile photo, once members have loaded.
    func avatarPath(of user: UUID) -> String? {
        members.first { $0.userId == user }?.profile?.avatarPath
    }
}
