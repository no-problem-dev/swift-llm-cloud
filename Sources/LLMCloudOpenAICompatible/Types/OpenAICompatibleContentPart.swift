import Foundation

/// One piece of a multipart message: text, an image, or audio.
///
/// Each case encodes as its own object with a `type` discriminator. An image travels under
/// `image_url`, which takes either a real URL or a `data:` URI carrying base64 bytes, so inline
/// images and hosted images use the same field. Audio travels under `input_audio` as base64 plus a
/// format name.
package enum OpenAICompatibleContentPart: Encodable, Sendable {
    case text(String)
    case imageUrl(url: String, detail: String?)
    case inputAudio(data: String, format: String)

    private struct TextPart: Encodable {
        let type: String = "text"
        let text: String
    }

    private struct ImageUrlPart: Encodable {
        let type: String = "image_url"
        let imageUrl: ImageUrl

        struct ImageUrl: Encodable {
            let url: String
            let detail: String?
        }

        enum CodingKeys: String, CodingKey {
            case type
            case imageUrl = "image_url"
        }
    }

    private struct InputAudioPart: Encodable {
        let type: String = "input_audio"
        let inputAudio: InputAudio

        struct InputAudio: Encodable {
            let data: String
            let format: String
        }

        enum CodingKeys: String, CodingKey {
            case type
            case inputAudio = "input_audio"
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(TextPart(text: text))
        case .imageUrl(let url, let detail):
            try container.encode(ImageUrlPart(imageUrl: .init(url: url, detail: detail)))
        case .inputAudio(let data, let format):
            try container.encode(InputAudioPart(inputAudio: .init(data: data, format: format)))
        }
    }
}
