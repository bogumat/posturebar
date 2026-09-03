import Foundation

struct CameraDescriptor: Equatable {
    let id: String
    let name: String
    let isExternal: Bool
}

enum CameraSelectionPolicy {
    static func preferredCamera(
        from cameras: [CameraDescriptor]
    ) -> CameraDescriptor? {
        cameras.first(where: \.isExternal) ?? cameras.first
    }
}
