import SwiftUI

private struct ScanRepositoryKey: EnvironmentKey {
    static var defaultValue: any ScanRepository = FakeScanRepository()
}

extension EnvironmentValues {
    var scanRepository: any ScanRepository {
        get { self[ScanRepositoryKey.self] }
        set { self[ScanRepositoryKey.self] = newValue }
    }
}

extension View {
    func scanRepository(_ repository: any ScanRepository) -> some View {
        environment(\.scanRepository, repository)
    }
}


