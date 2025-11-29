# Network Automation Scripts (NABLAC)

A collection of Tcl/Expect scripts for automating network device management, including configuration backup, IP address extraction, clock synchronization and more.

## Requirements

*   **Tcl**: Tool Command Language interpreter.
*   **Expect**: Extension for automating interactive applications.
*   **SQLite3**: Database engine for storing device and credential information.

## Setup

1.  **Clone the repository:**
    ```bash
    git clone --depth 1 https://github.com/zengxinhui/nablac.git
    cd nablac
    ```

2.  **Initialize the database:**
    Create the SQLite database (`net.db`) using the provided schema.
    ```bash
    sqlite3 net.db < db_schema.sql
    ```

3.  **Add Credentials:**
    Insert your network device credentials into the database. You can add multiple credentials; the scripts will try them in order of frequency.
    ```bash
    sqlite3 net.db "INSERT INTO cred (username, password, enable) VALUES ('myuser', 'mypass', 'myenable');"
    ```

4.  **Create dirs:**
    Prepare the directories for storing configs and stats.
    ```bash
    mkdir configs stats
    ```

## Usage

### 1. Device Discovery & Database Population (`fp.tcl`)

Use `fp.tcl` to attempt to log in to a device (by IP or hostname). If successful, it adds the device to the database or updates its existing record.

**Usage:**
```bash
./fp.tcl <hostname_or_ip> [findonly]
```

*   **`<hostname_or_ip>`**: The IP address or hostname of the device.
*   **`[findonly]`**: (Optional) If set (e.g., to `findonly`), the script checks if the device is already in the database and report back credentials to use to login to the device without updating the database.

**Example:**
```bash
./fp.tcl 192.168.1.1
```

### 2. Configuration Backup (`gc.tcl`)

Use `gc.tcl` to back up running configurations and extract IP information. It defaults to processing a subset (1/30th) of devices each run to spread the load, or you can specify specific device IDs.

**Usage:**
```bash
./gc.tcl [dev_id1,dev_id2,...]
```

*   **`[dev_id_list]`**: (Optional) A comma-separated list of device IDs to process immediately. If omitted, it processes a batch of devices based on `last_check` time.

**Example:**
```bash
./gc.tcl          # Process a batch of devices
./gc.tcl 1,5,10   # Process devices with IDs 1, 5, and 10
```

**Output:**
*   **Configs**: Saved in `configs/<hostname> <ip>`
*   **Stats**: Saved in `stats/<hostname> <ip>` (contains command outputs like `sh ver`, `sh route`, etc.)

### 3. Clock Synchronization (`fixclock.tcl`)

An example automation script that logs in to a specific device and synchronizes its clock to the local system time.

**Usage:**
```bash
./fixclock.tcl <ip_address>
```

**Example:**
```bash
./fixclock.tcl 192.168.1.1
```

## Database Schema

The `net.db` database contains three main tables:

*   **`cred`**: Stores login credentials (username, password, enable secret).
*   **`devices`**: Stores device inventory (hostname, IP, associated credential ID).
*   **`ip`**: Stores IP addresses and subnet masks extracted from device configurations.

## Files

*   `fp.tcl`: **F**ind **P**robe - Discovery and DB population.
*   `gc.tcl`: **G**et **C**onfig - Backup and stats collection.
*   `fixclock.tcl`: Automation example for setting clock.
*   `util.tcl`: Common utility functions (login, database connection, IP parsing).
*   `db_schema.sql`: SQL schema for initializing `net.db`.

   