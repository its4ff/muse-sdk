//
//  ShareMuseRenderer.swift
//  muse
//
//  Renders ShareableMuseView to high-resolution images for export
//

import SwiftUI
import Photos

@MainActor
final class ShareMuseRenderer {

    /// Renders a ShareableMuseView to a UIImage at high resolution
    static func render(_ view: ShareableMuseView) -> UIImage? {
        let renderer = ImageRenderer(content: view)

        // High-quality export (2x or 3x scale)
        renderer.scale = UIScreen.main.scale

        // Opaque background for better quality and smaller file size
        renderer.isOpaque = true

        return renderer.uiImage
    }

    /// Saves the rendered card to Photos library
    static func saveToPhotos(_ view: ShareableMuseView) async throws {
        guard let image = render(view) else {
            throw ShareMuseError.renderFailed
        }
        try await saveImageToLibrary(image)
    }

    /// Request photo library access and save image
    private static func saveImageToLibrary(_ image: UIImage) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)

        guard status == .authorized else {
            throw ShareMuseError.photoLibraryAccessDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}

// MARK: - Error Handling

enum ShareMuseError: LocalizedError {
    case renderFailed
    case photoLibraryAccessDenied

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            return "Failed to create shareable image"
        case .photoLibraryAccessDenied:
            return "Photo library access denied. Please enable it in Settings."
        }
    }
}
