//
//  FilenameGenerator.m
//  MboxChatCLI
//
//  Filename generation utility implementation
//

#import "FilenameGenerator.h"
#import "TextProcessor.h"

const NSUInteger kMaxFilenameLength = 48;

@implementation FilenameGenerator

+ (NSString *)safeExportFilename:(NSString *)subject threadNumber:(NSUInteger)threadNumber {
    NSString *base = subject.length > 0 ? subject : [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNumber];
    NSString *sanitized = [self sanitizeForFilename:base];

    if (sanitized.length > kMaxFilenameLength) {
        sanitized = [sanitized substringToIndex:kMaxFilenameLength];
    }

    if (sanitized.length == 0) {
        sanitized = [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNumber];
    }

    return [NSString stringWithFormat:@"export %@.txt", sanitized];
}

+ (NSString *)safeWriteFilename:(NSUInteger)messageNumber {
    return [NSString stringWithFormat:@"message%04lu.txt", (unsigned long)messageNumber];
}

+ (NSString *)safeSummaryFilename:(NSString *)subject threadNumber:(NSUInteger)threadNumber {
    NSString *base = subject.length > 0 ? subject : [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNumber];
    NSString *sanitized = [self sanitizeForFilename:base];

    if (sanitized.length > kMaxFilenameLength) {
        sanitized = [sanitized substringToIndex:kMaxFilenameLength];
    }

    if (sanitized.length == 0) {
        sanitized = [NSString stringWithFormat:@"thread%04lu", (unsigned long)threadNumber];
    }

    return [NSString stringWithFormat:@"summary %@.txt", sanitized];
}

+ (NSString *)sanitizeForFilename:(NSString *)input {
    // Strip non-ASCII first
    NSString *stripped = [TextProcessor stripNonASCII:input];

    // Define forbidden characters for filenames
    NSCharacterSet *forbidden = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>\'"];

    // Replace forbidden characters with underscores
    NSArray *parts = [stripped componentsSeparatedByCharactersInSet:forbidden];
    NSString *clean = [parts componentsJoinedByString:@"_"];

    return clean;
}

@end
