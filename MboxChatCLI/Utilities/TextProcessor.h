//
//  TextProcessor.h
//  MboxChatCLI
//
//  Utility class for text processing and cleaning operations
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Provides text processing utilities for cleaning and validating email content.
 *
 * @discussion This class handles:
 * - ASCII validation and conversion
 * - Non-printable character removal
 * - RTF and attachment stripping
 * - General text sanitization
 */
@interface TextProcessor : NSObject

/**
 * Checks if a string contains only clear text (printable ASCII + whitespace).
 *
 * @param string The string to validate
 * @return YES if the string is clear text, NO if it contains binary data
 *
 * @discussion Allowed characters:
 * - Printable ASCII (0x20-0x7E)
 * - Tab (0x09)
 * - Line feed (0x0A)
 * - Carriage return (0x0D)
 */
+ (BOOL)isClearText:(NSString *)string;

/**
 * Strips all non-ASCII characters from a string.
 *
 * @param input The string to process
 * @return A new string containing only ASCII characters
 *
 * @discussion Preserves:
 * - Printable ASCII (0x20-0x7E)
 * - Newline, carriage return, tab
 */
+ (NSString *)stripNonASCII:(NSString *)input;

/**
 * Removes RTF content and attachments from email body.
 *
 * @param body The email body content
 * @return Cleaned body with RTF and attachments removed
 *
 * @discussion Removes:
 * - application/rtf content sections
 * - multipart/mixed sections
 * - attachment declarations
 */
+ (NSString *)removeAttachmentsAndRTF:(NSString *)body;

/**
 * Trims whitespace and newlines from both ends of a string.
 *
 * @param string The string to trim
 * @return Trimmed string
 */
+ (NSString *)trim:(NSString *)string;

/**
 * Extracts the first reasonably long sentence from text.
 *
 * @param text The text to search
 * @return The first sentence (>8 characters), or empty string if none found
 *
 * @discussion Sentence boundaries: . ! ?
 */
+ (NSString *)firstSentenceFromText:(NSString *)text;

/**
 * Extracts the last reasonably long sentence from text.
 *
 * @param text The text to search
 * @return The last sentence (>8 characters), or empty string if none found
 *
 * @discussion Sentence boundaries: . ! ?
 */
+ (NSString *)lastSentenceFromText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
