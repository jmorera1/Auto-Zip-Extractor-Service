**Auto Zip Extractor Service **
I've created a simplified version of the script while maintaining all the key functionality. Here's an overview of how it works:
How It Works
1. **Real-Time Monitoring**
The script uses inotifywait to monitor the specified directory and all its subdirectories for file system events. When a new zip file appears (either created or copied), the script detects it immediately - no need to poll every 60 seconds.
2. **Duplicate Prevention**
**The script prevents re-extracting zip files using two methods:
**
**Checksum tracking:** Calculates an MD5 hash of each processed zip file and stores it in a database
**Directory pattern matching:** Checks if a directory matching the pattern zipname_YYYYMMDD* already exists

3. **Safe Extraction Process**
Before extracting, the script:

Verifies the file is actually a zip archive
Waits for the file to stabilize (ensures it's fully uploaded/copied)
Creates a timestamped extraction directory
Extracts the contents
Records the successful extraction

4. **Notification System**

Sends success emails to administrators
Sends failure alerts to a separate address
Includes relevant details about the extraction

5. **Parallel Processing**

Extracts multiple zip files simultaneously for efficiency
Limits the number of concurrent extractions to prevent system overload

6. **System Service Integration**

Runs as a systemd service for automatic startup
Includes proper logging and restart capability

**Installation Steps**

**Install the required dependencies:**
sudo yum install inotify-tools mailx

**Copy the script to your system:**
sudo cp auto-zip-extractor.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/auto-zip-extractor.sh

**Create the service file:**
sudo cp auto-zip-extractor.service /etc/systemd/system/

**Configure the script by editing the CONFIGURATION section at the top**:
sudo nano /usr/local/bin/auto-zip-extractor.sh

**Enable and start the service:**
sudo systemctl daemon-reload
sudo systemctl enable auto-zip-extractor.service
sudo systemctl start auto-zip-extractor.service

**Check the status:**
sudo systemctl status auto-zip-extractor.service

**View logs:**
sudo journalctl -u auto-zip-extractor.service -f


This version maintains all the core functionality while being more concise and easier to understand. The parallel processing has been simplified to use basic job control rather than the more complex semaphore system, making the script more maintainable.
