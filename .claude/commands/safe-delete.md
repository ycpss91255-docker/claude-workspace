Delete files safely using trash instead of rm.

When deleting files or directories, follow this priority:
1. Use `trash-put` if available (preferred — files go to system trash, recoverable)
2. Use `gio trash` if trash-put is not available
3. Use `rm` only as last resort when neither trash command exists

Usage: /safe-delete <file_or_directory_paths>

For the given paths: $ARGUMENTS

Run the appropriate command to delete them safely.
