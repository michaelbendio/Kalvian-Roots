import CryptoKit
import Foundation

/// Exact editorial source text is kept outside AI-parsed genealogical facts.
/// Old printed claims in the correction must never recreate withdrawn links.
public struct JuuretEditorialSource: Codable, Hashable, Sendable {
  public let workingText: String
  public let correctionText: String
  public let blockSHA256: String

  public init?(rawText: String) {
    let lines = rawText.components(separatedBy: "\n")
    guard let index = lines.firstIndex(where: {
      $0.hasPrefix("Research correction,") || $0.hasPrefix("*) Research correction,")
    }) else { return nil }
    workingText = lines[..<index].joined(separator: "\n")
    correctionText = lines[index...].joined(separator: "\n")
    blockSHA256 = SHA256.hash(data: Data(rawText.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// A review result, deliberately distinct from a book-only citation.
  /// Attribution comes from the exact approved editorial evidence, not AI prose.
  public var citationReviewText: String {
    """
    REVIEW REQUIRED — corrected Juuret working genealogy
    This is a mixed-source research draft, not a transcription or a book-only citation.
    Review the printed claims, editorial corrections, and evidence links below before attachment.

    Current canonical working text (including electronic FamilySearch annotations):
    \(workingText)

    Printed claims, editorial corrections, uncertainties, and supporting evidence (exact editorial note):
    \(correctionText)
    """.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
