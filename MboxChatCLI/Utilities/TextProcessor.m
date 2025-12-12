//
//  TextProcessor.m
//  MboxChatCLI
//
//  Text processing utility implementation
//

#import "TextProcessor.h"

@implementation TextProcessor

+ (BOOL)isClearText:(NSString *)string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    const uint8_t *bytes = data.bytes;
    NSUInteger len = data.length;

    for (NSUInteger i = 0; i < len; ++i) {
        uint8_t byte = bytes[i];

        // Allow printable ASCII (0x20-0x7E)
        if (byte >= 0x20 && byte <= 0x7E) {
            continue;
        }

        // Allow tab, line feed, carriage return
        if (byte == 0x09 || byte == 0x0A || byte == 0x0D) {
            continue;
        }

        // Any other byte is considered binary
        return NO;
    }

    return YES;
}

+ (NSString *)stripNonASCII:(NSString *)input {
    NSMutableString *result = [NSMutableString string];
    NSUInteger len = [input length];

    for (NSUInteger i = 0; i < len; ++i) {
        unichar c = [input characterAtIndex:i];

        // Keep printable ASCII
        if ((c >= 0x20 && c <= 0x7E) || c == '\n' || c == '\r' || c == '\t') {
            [result appendFormat:@"%C", c];
        }
    }

    return result;
}

+ (NSString *)removeAttachmentsAndRTF:(NSString *)body {
    NSMutableString *clean = [NSMutableString stringWithString:body];

    // Remove RTF sections
    NSRange rtfRange;
    while ((rtfRange = [clean rangeOfString:@"Content-Type: application/rtf"
                                     options:NSCaseInsensitiveSearch]).location != NSNotFound) {
        NSRange after = NSMakeRange(rtfRange.location, clean.length - rtfRange.location);
        NSRange boundary = [clean rangeOfString:@"\n--" options:0 range:after];
        NSRange partEnd = boundary.location != NSNotFound ? boundary : NSMakeRange(clean.length, 0);
        [clean deleteCharactersInRange:NSMakeRange(rtfRange.location, partEnd.location - rtfRange.location)];
    }

    // Remove multipart/mixed sections
    NSRange multi = [clean rangeOfString:@"Content-Type: multipart/mixed"
                                 options:NSCaseInsensitiveSearch];
    if (multi.location != NSNotFound) {
        [clean deleteCharactersInRange:NSMakeRange(multi.location, clean.length - multi.location)];
    }

    // Remove attachments
    NSRange att = [clean rangeOfString:@"Content-Disposition: attachment"
                               options:NSCaseInsensitiveSearch];
    if (att.location != NSNotFound) {
        [clean deleteCharactersInRange:NSMakeRange(att.location, clean.length - att.location)];
    }

    return clean;
}

+ (NSString *)trim:(NSString *)string {
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)firstSentenceFromText:(NSString *)text {
    if (!text || text.length == 0) {
        return @"";
    }

    NSArray *sentences = [text componentsSeparatedByCharactersInSet:
                          [NSCharacterSet characterSetWithCharactersInString:@".!?"]];

    for (NSString *sentence in sentences) {
        NSString *trimmed = [self trim:sentence];
        if (trimmed.length > 8) {
            return trimmed;
        }
    }

    return @"";
}

+ (NSString *)lastSentenceFromText:(NSString *)text {
    if (!text || text.length == 0) {
        return @"";
    }

    NSArray *sentences = [text componentsSeparatedByCharactersInSet:
                          [NSCharacterSet characterSetWithCharactersInString:@".!?"]];

    // Search backwards for first valid sentence
    for (NSInteger i = sentences.count - 1; i >= 0; i--) {
        NSString *sentence = sentences[i];
        NSString *trimmed = [self trim:sentence];
        if (trimmed.length > 8) {
            return trimmed;
        }
    }

    return @"";
}

@end
