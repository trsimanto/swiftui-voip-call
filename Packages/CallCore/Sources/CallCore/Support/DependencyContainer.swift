import Foundation

/// Deliberately small service locator used only at the composition root.
///
/// Types never reach into the container themselves; they receive their
/// dependencies through initialisers. The container just centralises how
/// those dependencies are built and which ones are shared.
@MainActor
public final class DependencyContainer {
    public enum Lifetime {
        /// Built once on first resolve, then reused.
        case singleton
        /// Built on every resolve.
        case transient
    }

    private struct Registration {
        let lifetime: Lifetime
        let factory: (DependencyContainer) -> Any
    }

    private var registrations: [String: Registration] = [:]
    private var singletons: [String: Any] = [:]

    public init() {}

    public func register<Service>(
        _ type: Service.Type,
        lifetime: Lifetime = .singleton,
        factory: @escaping (DependencyContainer) -> Service
    ) {
        let key = Self.key(for: type)
        registrations[key] = Registration(lifetime: lifetime, factory: { factory($0) })
        singletons[key] = nil
    }

    public func resolve<Service>(_ type: Service.Type = Service.self) -> Service {
        guard let service = resolveIfRegistered(type) else {
            preconditionFailure("No registration for \(Self.key(for: type)). Register it in the composition root.")
        }
        return service
    }

    public func resolveIfRegistered<Service>(_ type: Service.Type = Service.self) -> Service? {
        let key = Self.key(for: type)
        guard let registration = registrations[key] else { return nil }

        if registration.lifetime == .singleton, let existing = singletons[key] as? Service {
            return existing
        }
        guard let service = registration.factory(self) as? Service else { return nil }
        if registration.lifetime == .singleton {
            singletons[key] = service
        }
        return service
    }

    public func isRegistered<Service>(_ type: Service.Type) -> Bool {
        registrations[Self.key(for: type)] != nil
    }

    private static func key<Service>(for type: Service.Type) -> String {
        String(reflecting: type)
    }
}
