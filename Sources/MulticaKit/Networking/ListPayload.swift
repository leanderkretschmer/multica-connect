import Foundation

/// A list the server may return bare or wrapped, without the client having to
/// know which.
///
/// Multica is not uniform about this: `/api/issues` answers
/// `{"issues": [...], "has_more": false}` while `/api/projects` answers a bare
/// array, and `/api/agents` and `/api/workspaces` wrap under their own name.
/// Betting on a convention per endpoint means one wrong guess blanks a screen
/// with "the server sent something this version cannot read".
///
/// So: accept a bare array, or an object with exactly one array in it, whatever
/// that key is called. A server that renames its envelope key, or starts or
/// stops wrapping, does not break the app.
public struct ListPayload<Element: Decodable>: Decodable {
    public let items: [Element]

    public init(items: [Element]) {
        self.items = items
    }

    public init(from decoder: any Decoder) throws {
        if let bare = try? [Element](from: decoder) {
            items = bare
            return
        }

        let container: KeyedDecodingContainer<AnyCodingKey>
        do {
            container = try decoder.container(keyedBy: AnyCodingKey.self)
        } catch {
            throw DecodingError.typeMismatch(
                [Element].self,
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected an array, or an object wrapping one."
                )
            )
        }

        // Prefer the conventional envelope keys, then fall back to whatever
        // key in the object holds an array.
        for key in ListPayload.preferredKeys {
            guard let coding = AnyCodingKey(stringValue: key),
                  container.contains(coding),
                  let list = try? container.decode([Element].self, forKey: coding)
            else { continue }
            items = list
            return
        }
        for key in container.allKeys {
            guard let list = try? container.decode([Element].self, forKey: key) else { continue }
            items = list
            return
        }

        throw DecodingError.typeMismatch(
            [Element].self,
            .init(
                codingPath: decoder.codingPath,
                debugDescription: "No array found in the response object. Keys: \(container.allKeys.map(\.stringValue).sorted())"
            )
        )
    }

    private static var preferredKeys: [String] {
        ["data", "items", "results"]
    }
}

/// A coding key for a name only known at run time.
struct AnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}
