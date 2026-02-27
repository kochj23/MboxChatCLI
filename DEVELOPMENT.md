# MboxChatCLI Development Guide

This document provides technical information for developers working on MboxChatCLI.

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Building the Project](#building-the-project)
3. [Code Structure](#code-structure)
4. [Development Workflow](#development-workflow)
5. [Testing](#testing)
6. [Code Style](#code-style)
7. [Debugging](#debugging)
8. [Performance Profiling](#performance-profiling)
9. [Contributing](#contributing)

---

## Architecture Overview

### Current Architecture (v1.0.0)

**Monolithic Design** - Single file implementation:
```
main.m (418 lines)
├── Email Model (NSObject class)
├── Text Processing Functions
│   ├── isClearText()
│   ├── stripNonASCII()
│   ├── removeAttachmentsAndRTF()
│   └── Filename generators
├── MBOX Parser
│   └── parseMbox()
├── Command Functions
│   ├── printHelp()
│   ├── writeMessagesToDirectory()
│   ├── writeThreadsToDirectory()
│   └── summarizeEmailsToDirectory()
└── Main Loop (CLI interface)
```

### Target Architecture (v1.1.0+)

**Modular Design** - Separation of concerns:
```
MboxChatCLI/
├── Models/
│   ├── Email.h/m              # Email data model
│   └── EmailThread.h/m        # Thread model (future)
├── Parsers/
│   ├── MboxParser.h/m         # MBOX parsing logic
│   └── StreamingParser.h/m    # Streaming parser (future)
├── Utilities/
│   ├── TextProcessor.h/m      # Text cleaning
│   └── FilenameGenerator.h/m  # Safe filenames
├── Commands/
│   ├── CommandProtocol.h      # Command interface
│   ├── SearchCommand.h/m      # Search operations
│   ├── ExportCommand.h/m      # Export operations
│   └── SummarizeCommand.h/m   # Summarization
├── CLI/
│   └── CommandLineInterface.h/m  # User interaction
└── main.m                     # Entry point (~20 lines)
```

**Design Patterns**:
- **Command Pattern**: For CLI commands
- **Strategy Pattern**: For different export formats
- **Factory Pattern**: For parser creation
- **Observer Pattern**: For progress notifications (future)

---

## Building the Project

### Prerequisites

- **Xcode 14.0+**: Download from Mac App Store
- **macOS 10.13+**: Development and runtime environment
- **Git**: For version control

### Build Steps

#### 1. Clone/Navigate to Project
```bash
cd ~/Desktop/xcode/MboxChatCLI
```

#### 2. Open in Xcode
```bash
open MboxChatCLI.xcodeproj
```

#### 3. Select Scheme
- Scheme: **MboxChatCLI**
- Destination: **My Mac**

#### 4. Build
- **⌘B**: Build
- **⌘R**: Build and Run
- **⌘U**: Build and Test (once tests are added)

### Build Configurations

**Debug** (default for development):
- Compiler optimizations: **-O0**
- Debug symbols: **Enabled**
- Assertions: **Enabled**
- Fast build times

**Release** (for distribution):
- Compiler optimizations: **-Os** (size)
- Debug symbols: **Stripped**
- Assertions: **Disabled**
- Smaller binary size

### Build Output Location
```
~/Library/Developer/Xcode/DerivedData/MboxChatCLI-{hash}/
└── Build/Products/
    ├── Debug/
    │   └── MboxChatCLI         # Debug build
    └── Release/
        └── MboxChatCLI         # Release build
```

### Command-Line Build

Using `xcodebuild`:
```bash
# Build debug version
xcodebuild -project MboxChatCLI.xcodeproj \
           -scheme MboxChatCLI \
           -configuration Debug \
           build

# Build release version
xcodebuild -project MboxChatCLI.xcodeproj \
           -scheme MboxChatCLI \
           -configuration Release \
           build

# Clean build
xcodebuild -project MboxChatCLI.xcodeproj \
           -scheme MboxChatCLI \
           clean
```

---

## Code Structure

### Current File Organization

```
MboxChatCLI/
├── MboxChatCLI.xcodeproj/
│   ├── project.pbxproj         # Xcode project file
│   └── project.xcworkspace/
├── MboxChatCLI/
│   └── main.m                  # All source code (418 lines)
├── README.md
├── CHANGELOG.md
├── DEVELOPMENT.md              # This file
└── ANALYSIS.md
```

### Planned Refactored Structure

```
MboxChatCLI/
├── MboxChatCLI.xcodeproj/
├── MboxChatCLI/
│   ├── main.m                  # Entry point
│   ├── Models/
│   │   ├── Email.h
│   │   ├── Email.m
│   │   ├── EmailThread.h
│   │   └── EmailThread.m
│   ├── Parsers/
│   │   ├── MboxParser.h
│   │   ├── MboxParser.m
│   │   ├── StreamingMboxParser.h
│   │   └── StreamingMboxParser.m
│   ├── Utilities/
│   │   ├── TextProcessor.h
│   │   ├── TextProcessor.m
│   │   ├── FilenameGenerator.h
│   │   └── FilenameGenerator.m
│   ├── Commands/
│   │   ├── CommandProtocol.h
│   │   ├── SearchCommand.h
│   │   ├── SearchCommand.m
│   │   ├── ExportCommand.h
│   │   ├── ExportCommand.m
│   │   ├── SummarizeCommand.h
│   │   └── SummarizeCommand.m
│   └── CLI/
│       ├── CommandLineInterface.h
│       └── CommandLineInterface.m
├── MboxChatCLITests/
│   ├── ModelTests/
│   ├── ParserTests/
│   ├── UtilityTests/
│   └── CommandTests/
├── docs/
│   ├── architecture.md
│   └── commands.md
└── test_data/
    └── sample.mbox             # Small test file
```

---

## Development Workflow

### 1. Feature Development

**Branch Strategy**:
```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Make changes
# ...

# Commit changes
git add .
git commit -m "Add: Your feature description"

# Push to remote
git push origin feature/your-feature-name
```

**Commit Message Format**:
```
<Type>: <Short description>

<Detailed description (optional)>

<Related issues (optional)>
```

**Types**:
- `Add:` New feature
- `Fix:` Bug fix
- `Refactor:` Code restructuring
- `Docs:` Documentation changes
- `Test:` Adding tests
- `Perf:` Performance improvements

### 2. Code Review Checklist

Before committing:
- [ ] Code compiles without warnings
- [ ] All tests pass (when tests are added)
- [ ] Code follows style guide (see below)
- [ ] Documentation updated (if needed)
- [ ] CHANGELOG.md updated (for user-facing changes)
- [ ] No debug code or commented-out sections
- [ ] Memory management verified (no leaks)

### 3. Testing Workflow

```bash
# Run all tests
xcodebuild test -scheme MboxChatCLI

# Run with code coverage
xcodebuild test -scheme MboxChatCLI -enableCodeCoverage YES

# Generate coverage report
xcrun xccov view --report --only-targets \
  ~/Library/Developer/Xcode/DerivedData/MboxChatCLI-*/Logs/Test/*.xcresult
```

---

## Testing

### Test Structure (Planned)

```
MboxChatCLITests/
├── ModelTests/
│   ├── EmailTests.m
│   └── EmailThreadTests.m
├── ParserTests/
│   ├── MboxParserTests.m
│   └── StreamingParserTests.m
├── UtilityTests/
│   ├── TextProcessorTests.m
│   └── FilenameGeneratorTests.m
├── CommandTests/
│   ├── SearchCommandTests.m
│   ├── ExportCommandTests.m
│   └── SummarizeCommandTests.m
└── IntegrationTests/
    └── EndToEndTests.m
```

### Test Data

**Location**: `test_data/`

**Files**:
- `sample.mbox` - Small test file (< 1MB)
- `malformed.mbox` - Edge cases and errors
- `large.mbox` - Performance testing (excluded from git)

**Creating Test Data**:
```bash
# Create small test file
cat > test_data/sample.mbox << 'EOF'
From sender@example.com Mon Jan 15 09:00:00 2024
From: sender@example.com
To: recipient@example.com
Subject: Test Email 1
Date: Mon, 15 Jan 2024 09:00:00 -0800

This is a test email body.

From sender2@example.com Mon Jan 16 10:00:00 2024
From: sender2@example.com
To: recipient@example.com
Subject: Test Email 2
Date: Mon, 16 Jan 2024 10:00:00 -0800

Another test email.
EOF
```

### Writing Tests

**Example Test** (XCTest):
```objective-c
#import <XCTest/XCTest.h>
#import "MboxParser.h"

@interface MboxParserTests : XCTestCase
@property MboxParser *parser;
@end

@implementation MboxParserTests

- (void)setUp {
    [super setUp];
    self.parser = [[MboxParser alloc] init];
}

- (void)tearDown {
    self.parser = nil;
    [super tearDown];
}

- (void)testParseValidMbox {
    NSString *testFile = @"test_data/sample.mbox";
    NSArray<Email *> *emails = [self.parser parseMbox:testFile];

    XCTAssertNotNil(emails, @"Emails should not be nil");
    XCTAssertEqual(emails.count, 2, @"Should parse 2 emails");

    Email *first = emails[0];
    XCTAssertEqualObjects(first.from, @"sender@example.com");
    XCTAssertEqualObjects(first.subject, @"Test Email 1");
}

- (void)testParseMalformedMbox {
    NSString *testFile = @"test_data/malformed.mbox";
    NSArray<Email *> *emails = [self.parser parseMbox:testFile];

    // Should handle errors gracefully
    XCTAssertNotNil(emails);
}

@end
```

---

## Code Style

### Objective-C Style Guide

#### 1. Naming Conventions

**Classes**: PascalCase
```objective-c
@interface MboxParser : NSObject
```

**Methods**: camelCase, descriptive
```objective-c
- (NSArray<Email *> *)parseMbox:(NSString *)path;
- (void)writeEmailsToDirectory:(NSString *)dirPath;
```

**Variables**: camelCase
```objective-c
NSString *filePath;
NSMutableArray *allEmails;
```

**Constants**: kPascalCase or ALL_CAPS
```objective-c
static const NSUInteger kMaxFileNameLength = 48;
#define MAX_BUFFER_SIZE 4096
```

#### 2. Code Formatting

**Braces**: K&R style (opening brace on same line)
```objective-c
if (condition) {
    // code
} else {
    // code
}

for (Email *email in emails) {
    // code
}
```

**Spacing**:
```objective-c
// Good
if (x == y) {
    z = a + b;
}

// Bad
if(x==y){
    z=a+b;
}
```

**Line Length**: Maximum 120 characters

**Indentation**: 4 spaces (no tabs)

#### 3. Documentation

**Header Comments**:
```objective-c
/**
 * Parses an MBOX file and returns an array of Email objects.
 *
 * @param path The file system path to the MBOX file
 * @return An array of Email objects, or empty array on error
 *
 * @discussion This method loads the entire file into memory.
 * For large files (>2GB), consider using StreamingMboxParser instead.
 */
- (NSArray<Email *> *)parseMbox:(NSString *)path;
```

**Inline Comments**:
```objective-c
// Parse the MBOX file in chunks
NSArray *chunks = [mbox componentsSeparatedByString:@"\nFrom "];

// Skip empty first chunk if present
if ([chunks count] > 0 && [chunks[0] length] == 0) {
    chunks = [chunks subarrayWithRange:NSMakeRange(1, [chunks count] - 1)];
}
```

#### 4. Memory Management

**Use ARC** (Automatic Reference Counting):
```objective-c
// Good - ARC manages memory
NSString *string = [[NSString alloc] initWithString:@"test"];

// No need for manual release/retain
```

**Avoid Retain Cycles**:
```objective-c
// Use weak references in blocks
__weak typeof(self) weakSelf = self;
[self performOperationWithBlock:^{
    [weakSelf doSomething];
}];
```

---

## Debugging

### Xcode Debugging

**Breakpoints**:
- **Regular**: Click line number gutter
- **Conditional**: Right-click breakpoint → "Edit Breakpoint"
- **Exception**: ⌘7 → + → Exception Breakpoint

**LLDB Commands**:
```lldb
# Print variable
(lldb) po variableName

# Print C string
(lldb) p (char *)string

# Continue execution
(lldb) c

# Step over
(lldb) n

# Step into
(lldb) s

# Backtrace
(lldb) bt
```

### Console Logging

**Current Debug Output**:
```objective-c
printf("[DEBUG] Attempting to load mbox file: %s\n", [path UTF8String]);
printf("[ERROR] Failed to load '%s': %s\n", [path UTF8String], [[err localizedDescription] UTF8String]);
printf("[INFO] Wrote %lu individual messages.\n", (unsigned long)emails.count);
```

**Recommended NSLog**:
```objective-c
NSLog(@"[DEBUG] Loading mbox file: %@", path);
NSLog(@"[ERROR] Failed to load '%@': %@", path, err.localizedDescription);
NSLog(@"[INFO] Wrote %lu messages", (unsigned long)emails.count);
```

### Memory Debugging

**Instruments**:
```bash
# Profile for memory leaks
xcodebuild -scheme MboxChatCLI \
           -configuration Debug \
           -destination "platform=macOS" \
           build

# Open in Instruments
open -a Instruments

# Select "Leaks" template
# Select target: MboxChatCLI
```

**Malloc Stack Logging**:
```bash
# Enable malloc stack logging
export MallocStackLogging=1

# Run app
./MboxChatCLI test.mbox

# Check for leaks
leaks MboxChatCLI
```

---

## Performance Profiling

### Time Profiler

1. **Product → Profile** (⌘I)
2. Select **Time Profiler** template
3. Click **Record**
4. Perform operations
5. Click **Stop**
6. Analyze call tree

**Hot Paths to Monitor**:
- `parseMbox:` - MBOX parsing
- `componentsSeparatedByString:` - String splitting
- `writeToFile:` - File I/O
- Thread grouping loops

### Allocations

**Monitor**:
- Memory usage during parsing
- Peak memory with large files
- Object allocations
- Retain/release patterns

**Optimization Targets**:
- Reduce string copies
- Reuse mutable arrays
- Release autorelease pools in loops

---

## Contributing

### Getting Started

1. **Fork the repository**
2. **Create a feature branch**
3. **Make changes**
4. **Write tests**
5. **Submit pull request**

### Pull Request Guidelines

**Title Format**:
```
[Type] Brief description
```

**Description Template**:
```markdown
## Description
Brief description of changes

## Motivation
Why is this change needed?

## Changes
- List of changes
- ...

## Testing
How was this tested?

## Screenshots (if UI changes)

## Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] No compiler warnings
- [ ] Code follows style guide
```

### Code Review Process

1. **Automated checks** (future: CI/CD)
2. **Peer review** by maintainer
3. **Testing** on target platform
4. **Approval** and merge

---

## Additional Resources

### MBOX Format
- [RFC 4155 - The MBOX Format](https://datatracker.ietf.org/doc/html/rfc4155)
- [Wikipedia: mbox](https://en.wikipedia.org/wiki/Mbox)

### Objective-C
- [Apple's Objective-C Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/ProgrammingWithObjectiveC/)
- [Cocoa Fundamentals Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CocoaFundamentals/)

### Testing
- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Testing with Xcode](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/testing_with_xcode/)

---

**Questions?** Review [ANALYSIS.md](ANALYSIS.md) for architecture details or [README.md](README.md) for usage information.
