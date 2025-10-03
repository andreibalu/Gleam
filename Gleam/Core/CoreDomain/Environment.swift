import SwiftUI

private struct ScanRepositoryKey: EnvironmentKey {
    static var defaultValue: any ScanRepository = FakeScanRepository()
}

private struct AuthRepositoryKey: EnvironmentKey {
    static var defaultValue: any AuthRepository = FakeAuthRepository()
}

extension EnvironmentValues {
    var scanRepository: any ScanRepository {
        get { self[ScanRepositoryKey.self] }
        set { self[ScanRepositoryKey.self] = newValue }
    }

    var authRepository: any AuthRepository {
        get { self[AuthRepositoryKey.self] }
        set { self[AuthRepositoryKey.self] = newValue }
    }
}

extension View {
    func scanRepository(_ repository: any ScanRepository) -> some View {
        environment(\.scanRepository, repository)
    }

    func authRepository(_ repository: any AuthRepository) -> some View {
        environment(\.authRepository, repository)
    }
}


