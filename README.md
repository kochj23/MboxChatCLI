# MboxChatCLI

![Build](https://github.com/kochj23/MboxChatCLI/actions/workflows/build.yml/badge.svg)

A powerful command-line tool for parsing, analyzing, and exporting MBOX email archives.

## Overview

MboxChatCLI is a native macOS command-line application written in Objective-C that allows you to work with MBOX email archive files. It provides searching, thread extraction, summarization, and export capabilities for email archives.

## Features

### Core Functionality
- ✅ **MBOX Parsing**: Reads standard MBOX format files
- ✅ **Multi-file Support**: Load multiple MBOX files in one session
- ✅ **Text Cleaning**: Automatically removes attachments, RTF, and non-ASCII characters
- ✅ **Thread Detection**: Groups emails by subject (case-insensitive)

### Search Capabilities
- **Search by Sender**: Find all emails from a specific sender
- **Search by Subject**: Find emails containing keywords in subject
- **Search by Body**: Count emails mentioning specific keywords in body

### Export Features
- **Individual Messages**: Export each message as a separate text file
- **Thread Export**: Export entire conversation threads as single files
- **Thread Summaries**: Generate summary files with thread metadata

## Installation

### Requirements
- macOS 10.13 (High Sierra) or later
- Xcode 14.0 or later (for building from source)

### Building from Source

1. Clone the repository:
   ```bash
   cd /Users/kochj/Desktop/xcode/MboxChatCLI
   ```

2. Open the Xcode project:
   ```bash
   open MboxChatCLI.xcodeproj
   ```

3. Build the project (⌘B) or run directly (⌘R)

4. The compiled binary will be in:
   ```
   ~/Library/Developer/Xcode/DerivedData/MboxChatCLI-.../Build/Products/Debug/MboxChatCLI
   ```

## Usage

### Starting the Application

**With MBOX file(s) as arguments**:
```bash
./MboxChatCLI /path/to/archive.mbox
./MboxChatCLI file1.mbox file2.mbox file3.mbox
```

**Interactive mode** (prompts for file path):
```bash
./MboxChatCLI
Enter path(s) to .mbox files (comma-separated): /path/to/archive.mbox
```

### Commands

Once loaded, use these commands:

#### Search Commands

**Search by sender**:
```
> from john
Found 42 emails from 'john'.
```

**Search by subject keyword**:
```
> subject urgent
Found 15 emails with 'urgent' in subject.
```

**Count keyword in body**:
```
> count deadline
23 emails mention 'deadline'.
```

#### Export Commands

**Write individual messages**:
```
> write /path/to/output/dir
[INFO] Wrote 1523 individual messages.
```
Creates: `message0001.txt`, `message0002.txt`, etc.

**Export threads**:
```
> export /path/to/output/dir
[INFO] Exported 342 threads (each as a single file named 'export ...').
```
Creates: `export Project_Alpha_Discussion.txt`, etc.

**Summarize threads**:
```
> summarize /path/to/output/dir
[INFO] Wrote summary of 342 threads.
```
Creates: `summary Project_Alpha_Discussion.txt`, etc.

#### Utility Commands

**Load additional MBOX file**:
```
> load /path/to/another.mbox
Now loaded 2845 emails (total).
```

**Show help**:
```
> help
Commands:
  load <mbox file>     - Load/add another mbox file
  from <sender>        - Count emails by sender
  ...
```

**Exit application**:
```
> exit
Bye!
```

## Examples

### Example 1: Find All Emails from a Specific Person

```bash
$ ./MboxChatCLI archive.mbox
Loaded 1523 emails.

> from alice@example.com
Found 87 emails from 'alice@example.com'.
```

### Example 2: Export All Project-Related Threads

```bash
> subject project alpha
Found 45 emails with 'project alpha' in subject.

> export ~/Desktop/ProjectAlpha
[INFO] Exported 12 threads (each as a single file named 'export ...').
```

### Example 3: Analyze Email Volume

```bash
> from bob
Found 234 emails from 'bob'.

> from alice
Found 189 emails from 'alice'.

> count meeting
156 emails mention 'meeting'.
```

### Example 4: Generate Thread Summaries

```bash
> summarize ~/Documents/EmailSummaries
[INFO] Wrote summary of 342 threads.
```

Each summary file contains:
```
Subject: Re: Q4 Budget Planning
Thread length: 8 message(s)
From: john@company.com (Mon, 15 Jan 2024 09:23:45 -0800)
To:   alice@company.com (Wed, 17 Jan 2024 14:32:10 -0800)
Thread began: We need to finalize the Q4 budget by next week
Thread ended: Great, I'll send the final numbers to finance tomorrow
```

## File Formats

### Input Format

**MBOX** - Standard UNIX mailbox format:
```
From sender@example.com Mon Jan 15 09:23:45 2024
From: sender@example.com
To: recipient@example.com
Subject: Test Email
Date: Mon, 15 Jan 2024 09:23:45 -0800

Email body content here.

From sender2@example.com Mon Jan 16 10:00:00 2024
From: sender2@example.com
...
```

### Output Formats

**Individual Messages** (`write` command):
```
From: john@example.com
Subject: Project Update
Date: Mon, 15 Jan 2024 09:23:45 -0800

Email body content (ASCII, no attachments)
```

**Thread Export** (`export` command):
```
----- Email #1 -----
From: john@example.com
Subject: Project Update
Date: Mon, 15 Jan 2024 09:23:45 -0800

First email body

----- Email #2 -----
From: alice@example.com
Subject: Re: Project Update
Date: Mon, 15 Jan 2024 14:30:12 -0800

Reply body
```

**Thread Summary** (`summarize` command):
```
Subject: Project Update
Thread length: 5 message(s)
From: john@example.com (Mon, 15 Jan 2024 09:23:45 -0800)
To:   alice@example.com (Wed, 17 Jan 2024 16:45:00 -0800)
Thread began: We need to discuss the project timeline
Thread ended: Sounds good, let's meet Thursday at 2pm
```

## Technical Details

### Text Processing

- **ASCII Conversion**: All output is converted to ASCII for maximum compatibility
- **Attachment Removal**: RTF content and file attachments are automatically stripped
- **Safe Filenames**: Special characters are replaced with underscores in filenames
- **Maximum Filename Length**: 48 characters (truncated if longer)

### Thread Detection

Emails are grouped into threads based on:
- **Subject matching** (case-insensitive)
- Emails with identical subjects are grouped together
- Each thread is sorted by date (oldest first)

### Memory Considerations

- All emails are loaded into memory
- For very large archives (>2GB), consider splitting the MBOX file first
- Future versions will include streaming support for large files

## Troubleshooting

### Problem: "File not found" error
**Solution**: Verify the MBOX file path is correct and file exists
```bash
ls -lh /path/to/your.mbox
```

### Problem: "Failed to load" error
**Solution**: Ensure the file is a valid MBOX format and readable
```bash
file /path/to/your.mbox
# Should show: "RFC 822 mail text" or similar
```

### Problem: No emails loaded (shows "Loaded 0 emails")
**Solutions**:
- Verify MBOX format starts with `From ` (with space)
- Check file encoding (should be UTF-8 or ASCII)
- Ensure emails are not binary-encoded

### Problem: Missing email content in exports
**Solution**: Binary or heavily-encoded emails are skipped. Check if original emails contain plain text.

### Problem: Exported filenames are garbled
**Solution**: Special characters and non-ASCII are replaced with underscores. This is intentional for filesystem compatibility.

## Limitations

### Current Limitations
- Loads entire MBOX file into memory (not suitable for files >4GB on 8GB RAM systems)
- Thread detection based on subject only (doesn't use Message-ID/In-Reply-To headers)
- No HTML rendering (HTML emails exported as raw HTML)
- No attachment extraction (attachments are removed)
- No date range filtering
- Search is case-insensitive substring match (no regex support yet)

### Planned Features
- Streaming parser for large files
- Advanced thread detection (Message-ID, In-Reply-To, References headers)
- Date range filtering
- Regex search support
- JSON/CSV export formats
- Attachment extraction option
- Progress indicators for large files

## Project Structure

```
MboxChatCLI/
├── README.md                      # This file
├── CHANGELOG.md                   # Version history
├── DEVELOPMENT.md                 # Developer documentation
├── ANALYSIS.md                    # Architecture analysis
├── MboxChatCLI.xcodeproj/         # Xcode project
└── MboxChatCLI/
    └── main.m                     # Main source file
```

## Contributing

### Reporting Issues
Please include:
- macOS version
- MBOX file size
- Steps to reproduce
- Expected vs actual behavior

### Development
See [DEVELOPMENT.md](DEVELOPMENT.md) for:
- Architecture overview
- Building instructions
- Testing guidelines
- Code style guide

## License

[Specify your license here]

## Version History

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

## Acknowledgments

- Built with Objective-C and Foundation framework
- MBOX format parsing based on RFC 4155
- Inspired by the need for local email archive analysis tools

---

**MboxChatCLI** - Powerful email archive analysis for macOS.

---

> **Disclaimer:** This is a personal project created on my own time. It is not affiliated with, endorsed by, or representative of my employer.
