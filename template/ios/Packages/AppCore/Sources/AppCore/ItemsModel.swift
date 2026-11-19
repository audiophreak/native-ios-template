import Foundation
import Observation

/// The list of the signed-in person's items and the actions on it. Errors the server explains (validation,
/// not found) keep the person where they are; a lost session is the app model's business, not this one's.
@MainActor
@Observable
public final class ItemsModel {
    public enum Phase: Equatable {
        case idle
        case loading
        case loaded
        case failed(AppError)
    }

    public private(set) var items: [Item] = []
    public private(set) var phase: Phase = .idle
    public private(set) var actionError: AppError?

    private let api: APIService

    public init(api: APIService) { self.api = api }

    public var isEmpty: Bool { phase == .loaded && items.isEmpty }

    public func load() async {
        phase = .loading
        do {
            items = try await api.listItems(limit: 100, offset: 0)
            phase = .loaded
        } catch let error as AppError {
            phase = .failed(error)
        } catch {
            phase = .failed(.invalidResponse("unexpected failure"))
        }
    }

    /// Returns true when the item was saved, so a form knows whether to close.
    public func create(title: String, body: String) async -> Bool {
        await act { items.insert(try await api.createItem(title: title, body: body), at: 0) }
    }

    public func update(_ item: Item, title: String, body: String) async -> Bool {
        await act {
            let saved = try await api.updateItem(id: item.id, title: title, body: body)
            if let index = items.firstIndex(where: { $0.id == saved.id }) { items[index] = saved }
        }
    }

    public func delete(_ item: Item) async {
        _ = await act {
            try await api.deleteItem(id: item.id)
            items.removeAll { $0.id == item.id }
        }
    }

    public func dismissActionError() { actionError = nil }

    private func act(_ work: () async throws -> Void) async -> Bool {
        actionError = nil
        do {
            try await work()
            return true
        } catch AppError.unauthenticated {
            return false  // the middleware has already ended the session; the app model shows the sign-in screen
        } catch let error as AppError {
            actionError = error
            return false
        } catch {
            actionError = .invalidResponse("unexpected failure")
            return false
        }
    }
}
