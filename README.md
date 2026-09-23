## Why isn't there an option to click "never"?

This script sets the "Pause updates" to the maximum value at every log-in, and only reminds the user to check the updates after a configurable threshold of days.

## Usage

The installer creates a task to execute the script at every log-in.

NOTE: The script will run at every log-in directly from: %MAIN_SCRIPT%, echo so if you move or delete it, the task will stop working correctly.