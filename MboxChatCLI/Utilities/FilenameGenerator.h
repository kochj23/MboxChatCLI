//
//  FilenameGenerator.h
//  MboxChatCLI
//
//  Utility class for generating safe filenames
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Maximum length for generated filenames (excluding extension)
 */
extern const NSUInteger kMaxFilenameLength;

/**
 * Provides utilities for generating safe, filesystem-compatible filenames.
 *
 * @discussion This class ensures filenames are:
 * - Free of forbidden characters (/, \, :, ?, %, *, |, ", <, >, ')
 * - Limited to reasonable length
 * - ASCII-only
 * - Unique (using counters)
 */
@interface FilenameGenerator : NSObject

/**
 * Generates a safe filename for exporting a thread.
 *
 * @param subject The email subject to base the filename on
 * @param threadNumber The thread number for uniqueness
 * @return A safe filename like "export Subject_Here.txt"
 *
 * @discussion
 * - Removes forbidden characters
 * - Truncates to 48 characters
 * - Prefixes with "export "
 * - Falls back to "thread0001" if subject is empty
 */
+ (NSString *)safeExportFilename:(NSString *)subject threadNumber:(NSUInteger)threadNumber;

/**
 * Generates a safe filename for writing an individual message.
 *
 * @param messageNumber The message number for uniqueness
 * @return A filename like "message0001.txt"
 */
+ (NSString *)safeWriteFilename:(NSUInteger)messageNumber;

/**
 * Generates a safe filename for a thread summary.
 *
 * @param subject The email subject to base the filename on
 * @param threadNumber The thread number for uniqueness
 * @return A safe filename like "summary Subject_Here.txt"
 *
 * @discussion Similar to safeExportFilename but prefixes with "summary "
 */
+ (NSString *)safeSummaryFilename:(NSString *)subject threadNumber:(NSUInteger)threadNumber;

/**
 * Sanitizes a string for use in a filename.
 *
 * @param input The string to sanitize
 * @return ASCII-only string with forbidden characters removed
 */
+ (NSString *)sanitizeForFilename:(NSString *)input;

@end

NS_ASSUME_NONNULL_END
