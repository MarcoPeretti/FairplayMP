# Update Log

## 2026-04-09: Communication Layer Improvements

### Client.java
- Added explicit connection timeout (5 seconds) to prevent indefinite blocking
- Added SSL handshake timeout (10 seconds) via `setSoTimeout()`
- Refactored to use explicit `SSLSocket` with proper handshake sequence
- Added error logging for failed connection attempts

### Msg.java
- Added caching for `BasicMsg` to avoid rebuilding the protobuf message on repeated calls to `getBasicMsg()`
- Removed destructive `_msg = null` that prevented message reuse

### Server.java
- Added try-catch around message parsing to handle connection errors gracefully
- Added debug logging for received messages showing message ID, sender IP, and total count

### Player.java
- Added debug logging for message waiting (expected count vs received count)
- Changed `msgs.wait()` to `msgs.wait(5000)` with periodic status logging to help diagnose hangs
- Logs when message collection is complete
